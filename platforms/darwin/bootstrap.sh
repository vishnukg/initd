#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"
DOCKER_CASK="docker-desktop"
DOCKER_APP="/Applications/Docker.app"
OH_MY_ZSH_DIR="${HOME}/.oh-my-zsh"
OH_MY_ZSH_REPO="https://github.com/ohmyzsh/ohmyzsh.git"

# Exported so scripts/link.sh reuses the same timestamped folder.
export BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/paths.sh"

# Script-scoped so the EXIT trap in main() can still reference it after main() returns.
work_brewfile=""

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
    log "Homebrew not found. Installing..."
    # NONINTERACTIVE suppresses the "Press RETURN to continue" prompt.
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Apple Silicon installs to /opt/homebrew; Intel to /usr/local.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  require_command brew "but was not found after Homebrew setup"
}

oh_my_zsh_is_installed() {
  local remote=""
  [[ -d "${OH_MY_ZSH_DIR}/.git" ]] || return 1
  remote="$(git -C "${OH_MY_ZSH_DIR}" remote get-url origin 2>/dev/null || true)"
  [[ "${remote}" == "${OH_MY_ZSH_REPO}" || "${remote}" == "git@github.com:ohmyzsh/ohmyzsh.git" ]]
}

ensure_oh_my_zsh() {
  if oh_my_zsh_is_installed && [[ -z "$(git -C "${OH_MY_ZSH_DIR}" status --porcelain)" ]]; then
    log "Updating Oh My Zsh in ${OH_MY_ZSH_DIR}."
    # --ff-only avoids creating a merge commit in the managed checkout.
    if git -C "${OH_MY_ZSH_DIR}" fetch --quiet origin \
       && git -C "${OH_MY_ZSH_DIR}" merge --ff-only --quiet '@{u}'; then
      return
    fi
    log_warn "Could not fast-forward Oh My Zsh; reinstalling."
  fi

  path_exists "${OH_MY_ZSH_DIR}" && backup_path "${OH_MY_ZSH_DIR}"
  log "Installing Oh My Zsh into ${OH_MY_ZSH_DIR}."
  git clone --quiet --depth=1 "${OH_MY_ZSH_REPO}" "${OH_MY_ZSH_DIR}"
}

main() {
  work_brewfile="$(mktemp)"
  # Also cleans up the .tmp file the Docker filter below may create.
  trap 'rm -f "${work_brewfile}" "${work_brewfile}.tmp"' EXIT

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for macOS."

  ensure_xcode_clt
  ensure_homebrew

  # If Docker.app exists outside Homebrew, strip the cask so brew bundle doesn't
  # fail trying to install into an already-occupied path.
  cp "${BREWFILE}" "${work_brewfile}"
  if [[ -d "${DOCKER_APP}" ]] && ! brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1; then
    log_warn "Skipping Docker cask: /Applications/Docker.app already exists outside Homebrew."
    grep -Ev "^[[:space:]]*cask[[:space:]]+[\"']${DOCKER_CASK}[\"'][[:space:]]*$" \
      "${work_brewfile}" > "${work_brewfile}.tmp"
    mv "${work_brewfile}.tmp" "${work_brewfile}"
  fi

  log "Installing Homebrew packages and casks..."
  brew bundle --file "${work_brewfile}"

  # brew bundle skips casks whose receipt exists even when the app was manually deleted.
  if brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1 && [[ ! -d "${DOCKER_APP}" ]]; then
    log_warn "Docker Desktop receipt exists but app is missing. Reinstalling..."
    brew reinstall --cask "${DOCKER_CASK}"
  fi

  require_command mise "after brew bundle"

  log "Ensuring Oh My Zsh is installed..."
  ensure_oh_my_zsh

  log "Linking managed configs into ${HOME}..."
  "${ROOT_DIR}/scripts/link.sh"

  log "Trusting shared mise config."
  mise trust "${ROOT_DIR}/mise/.config/mise/config.toml"

  log "Installing shared runtimes with mise..."
  mise install --yes

  log "Applying macOS defaults..."
  "${ROOT_DIR}/platforms/darwin/macos.sh"

  echo
  log_success "initd finished for macOS."
}

main "$@"
