#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

BREWFILE="${ROOT_DIR}/Brewfile"
DOCKER_CASK="docker-desktop"
DOCKER_APP="/Applications/Docker.app"

# Exported so scripts/link.sh reuses the same timestamped folder.
# $$ (PID) suffix prevents collision when bootstrap is re-run within the same second.
export BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S).$$"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/managed-configs.sh"

# Script-scoped so the EXIT trap in main() can still reference it after main() returns.
brewfile_tmp=""

ensure_macos() {
  if [[ "${OS}" == "Darwin" ]]; then
    log "Detected macOS."
    return
  fi

  log_error "Unsupported operating system: ${OS}. This bootstrap currently supports macOS only."
  exit 1
}

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log_success "Xcode Command Line Tools already installed."
    return
  fi

  log_warn "Xcode Command Line Tools are required. Launching installer..."
  # --install exits non-zero if an install is already in progress; || true prevents set -e from aborting.
  xcode-select --install || true
  log_info "Finish the Xcode Command Line Tools install, then re-run ./bootstrap.sh"
  exit 1
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log_success "Homebrew already installed."
  else
    require_command curl "to install Homebrew"
    log "Homebrew not found. Installing..."
    # NONINTERACTIVE suppresses the "Press RETURN to continue" prompt.
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

  # Register fish as an allowed shell so chsh accepts it
  if ! grep -qxF "${fish_path}" /etc/shells; then
    log "Adding ${fish_path} to /etc/shells."
    printf '%s\n' "${fish_path}" | sudo tee -a /etc/shells > /dev/null \
      || { log_error "Failed to add fish to /etc/shells — check sudo access."; exit 1; }
  else
    log_success "fish already in /etc/shells."
  fi

  # dscl avoids the interactive password prompt that chsh requires
  if [[ "${SHELL}" != "${fish_path}" ]]; then
    log "Setting fish as default shell for ${USER}."
    sudo dscl . -create "/Users/${USER}" UserShell "${fish_path}" \
      || { log_error "Failed to set fish as default shell via dscl — check sudo access."; exit 1; }
  else
    log_success "fish is already the default shell."
  fi

  # Authenticate fisher with the gh CLI token so it doesn't hit GitHub rate
  # limits. Scoped to this subprocess only — GITHUB_TOKEN is never set globally.
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

  log "Authenticating gh CLI (used by mise and fisher to avoid GitHub API rate limits)..."
  gh auth login
}

setup_git_profile() {
  local existing_email
  existing_email="$(git config --file "${ROOT_DIR}/git/local.gitconfig" user.email 2>/dev/null || true)"

  if git_profile_link_is_managed "${HOME}/.gitconfig" && [[ -n "${existing_email}" ]]; then
    log_success "Git profile already configured (${existing_email})."
    return
  fi

  log "Setting up Git profile..."
  local git_profile
  printf '%b::%b Machine type [personal/work] (default: personal): ' "${INITD_CYAN}" "${INITD_RESET}"
  read -r git_profile
  git_profile="${git_profile:-personal}"
  "${ROOT_DIR}/scripts/git-profile.sh" "${git_profile}"
}

main() {
  ensure_macos

  brewfile_tmp="$(mktemp)" || { log_error "Failed to create temporary Brewfile."; exit 1; }
  # Also cleans up the .tmp file the Docker filter below may create.
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
    grep -Ev "^[[:space:]]*cask[[:space:]]+[\"']${DOCKER_CASK}[\"'][[:space:]]*$" \
      "${brewfile_tmp}" > "${brewfile_tmp}.tmp"
    mv "${brewfile_tmp}.tmp" "${brewfile_tmp}"
  fi

  log "Installing Homebrew packages and casks..."
  brew bundle --file "${brewfile_tmp}"

  # brew bundle skips casks whose receipt exists even when the app was manually deleted.
  if brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1 && [[ ! -d "${DOCKER_APP}" ]]; then
    log_warn "Docker Desktop receipt exists but app is missing. Reinstalling..."
    brew reinstall --cask "${DOCKER_CASK}"
  fi

  require_command mise "after brew bundle"

  log "Linking managed configs into ${HOME}..."
  "${ROOT_DIR}/scripts/link.sh"

  log "Authenticating gh CLI..."
  ensure_gh_auth

  log "Ensuring fish shell is configured..."
  ensure_fish

  log "Trusting shared mise config."
  mise trust "${ROOT_DIR}/mise/.config/mise/config.toml"

  log "Installing shared runtimes and LSP tooling with mise..."
  mise install --yes

  log "Applying macOS defaults..."
  "${ROOT_DIR}/scripts/macos.sh"

  setup_git_profile

  echo
  log_success "initd finished for macOS."
}

main "$@"
