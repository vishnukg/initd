#!/usr/bin/env bash
set -euo pipefail

# macOS platform bootstrap. Invoked by the top-level dispatcher when uname=Darwin.
# Anything macOS-specific stays inside this directory.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="${ROOT_DIR}/macos"
SHARED_DIR="${ROOT_DIR}/shared"

BREWFILE="${MACOS_DIR}/Brewfile"
DOCKER_CASK="docker-desktop"
DOCKER_APP="/Applications/Docker.app"

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
  if command -v brew >/dev/null 2>&1; then
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

  # Apple Silicon installs to /opt/homebrew; Intel to /usr/local.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  require_command brew "but was not found after Homebrew setup"
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

setup_git_profile() {
  local local_gitconfig="${SHARED_DIR}/configs/git/local.gitconfig"
  local existing_email
  existing_email="$(git config --file "${local_gitconfig}" user.email 2>/dev/null || true)"

  if git_profile_link_is_managed "${HOME}/.gitconfig" && [[ -n "${existing_email}" ]]; then
    log_success "Git profile already configured (${existing_email})."
    return
  fi

  if [[ ! -t 0 ]]; then
    log_warn "Git profile needs setup, but bootstrap is not running interactively."
    log_info "Run shared/lib/git-profile.sh personal or work later."
    return
  fi

  log "Setting up Git profile..."
  local git_profile
  printf '%b::%b Machine type [personal/work] (default: personal): ' "${INITD_CYAN}" "${INITD_RESET}"
  read -r git_profile
  git_profile="${git_profile:-personal}"
  "${SHARED_DIR}/lib/git-profile.sh" "${git_profile}"
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

  # If Docker.app exists outside Homebrew, strip the cask so brew bundle doesn't
  # fail trying to install into an already-occupied path.
  cp "${BREWFILE}" "${brewfile_tmp}"
  if [[ -d "${DOCKER_APP}" ]] && ! brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1; then
    log_warn "Skipping Docker cask: /Applications/Docker.app already exists outside Homebrew."
    if grep -Ev "^[[:space:]]*cask[[:space:]]+[\"']${DOCKER_CASK}[\"'][[:space:]]*$" \
        "${brewfile_tmp}" > "${brewfile_tmp}.tmp" && [[ -s "${brewfile_tmp}.tmp" ]]; then
      mv "${brewfile_tmp}.tmp" "${brewfile_tmp}"
    fi
  fi

  log "Installing Homebrew packages and casks..."
  brew bundle --file "${brewfile_tmp}"

  if brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1 && [[ ! -d "${DOCKER_APP}" ]]; then
    log_warn "Docker Desktop receipt exists but app is missing. Reinstalling..."
    brew reinstall --cask "${DOCKER_CASK}"
  fi

  require_command mise "after brew bundle"

  log "Linking managed configs into ${HOME}..."
  "${SHARED_DIR}/lib/link.sh" macos

  log "Checking gh CLI authentication..."
  ensure_gh_auth

  log "Ensuring fish shell is configured..."
  ensure_fish

  log "Trusting shared mise config."
  mise trust "${SHARED_DIR}/configs/mise/.config/mise/config.toml"

  log "Installing shared runtimes and LSP tooling with mise..."
  mise install --yes

  log "Applying macOS defaults..."
  "${MACOS_DIR}/defaults.sh"

  setup_git_profile

  echo
  log_success "initd finished for macOS."
}

main "$@"
