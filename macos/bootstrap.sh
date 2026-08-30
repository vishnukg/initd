#!/usr/bin/env bash
set -euo pipefail

# macOS platform bootstrap. Invoked by the top-level dispatcher when uname=Darwin.
# Anything macOS-specific stays inside this directory.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="${ROOT_DIR}/macos"
SHARED_DIR="${ROOT_DIR}/shared"

BREWFILE="${MACOS_DIR}/Brewfile"
CHROME_CASK="google-chrome"
CHROME_APP="/Applications/Google Chrome.app"

# Exported so shared/lib/link.sh reuses the same timestamped folder.
export BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S).$$}"

# shellcheck disable=SC1091
source "${SHARED_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${SHARED_DIR}/managed-links.sh"

brewfile_tmp=""

ensure_user_context() {
  if [[ "${EUID}" == "0" ]]; then
    log_error "Do not run bootstrap with sudo. It manages files and login shell settings for your normal user."
    exit 1
  fi
}

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log_success "Xcode Command Line Tools already installed."
    return
  fi

  log_warn "Xcode Command Line Tools are required. Launching installer..."
  xcode-select --install || true
  log_info "Finish the Xcode Command Line Tools install, then re-run bootstrap.sh"
  exit 1
}

ensure_homebrew() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    log_success "Homebrew already installed."
  else
    require_command curl "to install Homebrew"
    log "Homebrew not found. Installing..."
    # NONINTERACTIVE=1 makes the installer probe sudo with `sudo -n`, which never
    # prompts — so on a fresh machine with no cached credential it fails with a
    # misleading "Need sudo access … needs to be an Administrator" even for admins.
    # Prime (and cache) the credential first so the installer sails through.
    sudo -v || { log_error "Need admin (sudo) access to install Homebrew."; exit 1; }
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL --max-time 60 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if [[ ! -x /opt/homebrew/bin/brew ]]; then
    log_error "Homebrew was not found at the Apple Silicon prefix /opt/homebrew after installation."
    exit 1
  fi

  eval "$(/opt/homebrew/bin/brew shellenv)"
}

ensure_fish() {
  require_command fish "after brew bundle"

  local fish_path
  fish_path="$(command -v fish)"
  local account_name="${USER:-$(id -un)}"

  if ! grep -qxF "${fish_path}" /etc/shells; then
    log "Adding ${fish_path} to /etc/shells."
    printf '%s\n' "${fish_path}" | sudo tee -a /etc/shells > /dev/null \
      || { log_error "Failed to add fish to /etc/shells — check sudo access."; exit 1; }
  else
    log_success "fish already in /etc/shells."
  fi

  # Read the saved login shell instead of $SHELL — $SHELL stays stale until the
  # user opens a new terminal, which would re-prompt for sudo on repeated runs.
  local login_shell
  login_shell="$(dscl . -read "/Users/${account_name}" UserShell 2>/dev/null | awk '{print $2}' || true)"

  if [[ "${login_shell}" != "${fish_path}" ]]; then
    log "Setting fish as default shell for ${account_name}."
    sudo dscl . -create "/Users/${account_name}" UserShell "${fish_path}" \
      || { log_error "Failed to set fish as default shell via dscl — check sudo access."; exit 1; }
  else
    log_success "fish is already the default shell."
  fi

  log "Syncing fisher plugins..."
  GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)" fish -c "
    if not functions -q fisher
      curl -fsSL --max-time 30 https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
      fisher install jorgebucaran/fisher
    end
    fisher update
  "
}

ensure_gh_auth() {
  require_command gh "after brew bundle"

  if gh auth token >/dev/null 2>&1; then
    log_success "gh auth check done."
    return
  fi

  if [[ ! -t 0 ]]; then
    log_warn "gh CLI is not authenticated, and bootstrap is not running interactively."
    log_info "Run gh auth login later, then re-run bootstrap.sh."
    return
  fi

  log "Authenticating gh CLI..."
  gh auth login
}

# Drop a cask from the temp Brewfile when its app already lives outside Homebrew,
# so brew bundle doesn't fail trying to install into an already-occupied path.
strip_cask_if_app_exists() {
  local cask="$1" app="$2"

  if [[ -d "${app}" ]] && ! brew list --cask "${cask}" >/dev/null 2>&1; then
    log_warn "Skipping ${cask} cask: ${app} already exists outside Homebrew."
    if grep -Ev "^[[:space:]]*cask[[:space:]]+[\"']${cask}[\"'][[:space:]]*$" \
        "${brewfile_tmp}" > "${brewfile_tmp}.tmp" && [[ -s "${brewfile_tmp}.tmp" ]]; then
      mv "${brewfile_tmp}.tmp" "${brewfile_tmp}"
    fi
  fi
}

# Two settings the docker formula needs that Docker Desktop used to provide:
# credsStore=osxkeychain so `docker login` stores tokens in the Keychain, and
# cliPluginsExtraDirs so the CLI finds brew-installed plugins (docker compose).
ensure_docker_config() {
  require_command docker-credential-osxkeychain "after brew bundle"

  local docker_config="${HOME}/.docker/config.json"
  mkdir -p "${HOME}/.docker"

  # Merge rather than overwrite: config.json also holds currentContext,
  # plugin hints, and any existing registry auths.
  python3 - "${docker_config}" <<'PY' \
    || { log_error "Failed to update ${docker_config}"; exit 1; }
import json
import os
import sys

path = sys.argv[1]
config = {}
if os.path.exists(path):
    with open(path) as f:
        config = json.load(f)

wanted = {
    "credsStore": "osxkeychain",
}
plugin_dir = "/opt/homebrew/lib/docker/cli-plugins"
plugin_dirs = config.get("cliPluginsExtraDirs", [])
if not isinstance(plugin_dirs, list):
    plugin_dirs = []
if plugin_dir not in plugin_dirs:
    plugin_dirs.append(plugin_dir)

wanted["cliPluginsExtraDirs"] = plugin_dirs
changed = any(config.get(k) != v for k, v in wanted.items())

if changed:
    config.update(wanted)
    with open(path, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")

# The file can contain registry auth material even when osxkeychain is the
# configured default, so keep it private whether or not its JSON changed.
os.chmod(path, 0o600)
PY

  log_success "Docker config OK (osxkeychain credsStore, brew CLI plugins dir)."
}

ensure_colima_service() {
  require_command colima "after brew bundle"

  # Homebrew refuses to manage services when it inherits TMUX, even though
  # launchd itself is independent of the terminal session. Strip only that
  # marker so bootstrap is safe to run from an existing tmux shell.
  if env -u TMUX brew services info colima --json 2>/dev/null | grep -q '"running": true'; then
    log_success "colima login service already running."
    return
  fi

  # Hand ownership to brew services if colima was started manually: the launchd
  # job runs `colima start -f`, which exits immediately when an instance is
  # already up, and launchd would respawn it in a loop.
  if colima status >/dev/null 2>&1; then
    log "Stopping manually-started colima before enabling the login service."
    colima stop
  fi

  log "Enabling colima as a login service (brew services)."
  env -u TMUX brew services start colima \
    || { log_error "Failed to start colima via brew services — check /opt/homebrew/var/log/colima.log"; exit 1; }
}

# Fonts that live in the repo (gitignored, machine-local — currently Berkeley
# Mono, see .gitignore) must be COPIED into ~/Library/Fonts: macOS silently
# refuses to register fonts reached through a symlink, whether the link is the
# directory or the file itself (verified — CoreText resolves the family to
# Helvetica until the real bytes are in place). So this is a copy step, not a
# MANAGED_LINKS entry. Idempotent: only copies files that are missing or stale.
ensure_local_fonts() {
  local src_dir="${SHARED_DIR}/fonts/berkeley-mono"
  local dst_dir="${HOME}/Library/Fonts"
  local src dst copied=0

  if [[ ! -d "${src_dir}" ]]; then
    log "No machine-local fonts to install (${src_dir} absent) — skipping."
    return
  fi

  mkdir -p "${dst_dir}"

  for src in "${src_dir}"/*.otf; do
    [[ -e "${src}" ]] || continue
    dst="${dst_dir}/$(basename "${src}")"
    if [[ ! -f "${dst}" ]] || ! cmp -s "${src}" "${dst}"; then
      cp "${src}" "${dst}"
      copied=$((copied + 1))
    fi
  done

  if (( copied > 0 )); then
    log_success "Installed ${copied} font file(s) into ${dst_dir}."
  else
    log_success "Machine-local fonts already installed."
  fi
}

setup_git_profile() {
  local local_gitconfig="${SHARED_DIR}/configs/git/local.gitconfig"
  local existing_email
  existing_email="$(git config --file "${local_gitconfig}" user.email 2>/dev/null || true)"

  if [[ -n "${existing_email}" ]]; then
    log_success "Git identity already configured (override email: ${existing_email})."
    return
  fi

  if [[ ! -t 0 ]]; then
    log_warn "Git identity needs setup, but bootstrap is not running interactively."
    log_info "Run shared/lib/git-profile.sh personal or work later."
    return
  fi

  log "Setting up Git identity..."
  "${SHARED_DIR}/lib/git-profile.sh"
}

main() {
  ensure_user_context

  if [[ ! -f "${BREWFILE}" ]]; then
    log_error "Brewfile not found: ${BREWFILE}"
    exit 1
  fi

  brewfile_tmp="$(mktemp)" || { log_error "Failed to create temporary Brewfile."; exit 1; }
  trap 'rm -f "${brewfile_tmp}" "${brewfile_tmp}.tmp"' EXIT

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for macOS."

  ensure_xcode_clt
  ensure_homebrew

  # Drop casks whose apps already exist outside Homebrew so brew bundle doesn't
  # fail trying to install into an already-occupied path.
  cp "${BREWFILE}" "${brewfile_tmp}"
  strip_cask_if_app_exists "${CHROME_CASK}" "${CHROME_APP}"

  log "Installing Homebrew packages and casks..."
  brew bundle --file "${brewfile_tmp}"

  require_command mise "after brew bundle"

  # gh auth comes BEFORE the fonts sync so a fresh interactive bootstrap gets
  # the licensed fonts in this same run. Both steps degrade gracefully when
  # auth is impossible (non-interactive: ensure_gh_auth warns and returns,
  # fonts.sh then warns and skips — re-run bootstrap after gh auth login).
  log "Checking gh CLI authentication..."
  ensure_gh_auth

  log "Syncing licensed fonts from private repo..."
  "${SHARED_DIR}/lib/fonts.sh"

  log "Linking managed configs into ${HOME}..."
  "${SHARED_DIR}/lib/link.sh" macos

  log "Installing licensed fonts into ~/Library/Fonts..."
  ensure_local_fonts

  log "Ensuring fish shell is configured..."
  ensure_fish

  log "Trusting shared mise config."
  mise trust "${SHARED_DIR}/configs/mise/.config/mise/config.toml"

  log "Installing shared runtimes and LSP tooling with mise..."
  mise install --yes

  log "Applying macOS defaults..."
  "${MACOS_DIR}/defaults.sh"

  setup_git_profile

  log "Configuring Docker CLI (credentials, plugins)..."
  ensure_docker_config

  log "Ensuring colima runs as a login service..."
  ensure_colima_service

  echo
  log_success "initd finished for macOS."
}

main "$@"
