#!/usr/bin/env bash
set -euo pipefail

# This script lives in platforms/darwin, so ../.. is the repository root.
# Using an absolute ROOT_DIR lets bootstrap be run from any directory.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"
DOCKER_CASK="docker-desktop"
DOCKER_APP="/Applications/Docker.app"
OH_MY_ZSH_DIR="${HOME}/.oh-my-zsh"
OH_MY_ZSH_REPO="https://github.com/ohmyzsh/ohmyzsh.git"

# One timestamp per run keeps all preserved user files grouped together.
# Exported so scripts/link.sh reuses the same folder.
export BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)"
WORK_BREWFILE=""

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/paths.sh"

require_command() {
  local command_name="$1"
  local context="$2"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log_error "${command_name} is required ${context}."
    exit 1
  fi
}

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log_success "Xcode Command Line Tools already installed."
    return
  fi

  log_warn "Xcode Command Line Tools are required. Launching installer..."
  # The installer command returns before the GUI install completes, and may also
  # report that installation is already in progress. Either way, the user must
  # finish it outside this script and rerun bootstrap.
  xcode-select --install || true
  log_info "Finish the Xcode Command Line Tools install, then re-run ./bootstrap.sh"
  exit 1
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log_success "Homebrew already installed."
  else
    log "Homebrew not found. Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Homebrew uses different default prefixes on Apple Silicon and Intel Macs.
  # Load whichever one exists so freshly installed tools are on PATH immediately.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  require_command brew "but was not found after Homebrew setup"
}

# True when ${OH_MY_ZSH_DIR} is a git checkout of the upstream Oh My Zsh repo.
oh_my_zsh_is_installed() {
  local remote=""

  [[ -d "${OH_MY_ZSH_DIR}/.git" ]] || return 1
  remote="$(git -C "${OH_MY_ZSH_DIR}" remote get-url origin 2>/dev/null || true)"
  [[ "${remote}" == "${OH_MY_ZSH_REPO}" || "${remote}" == "git@github.com:ohmyzsh/ohmyzsh.git" ]]
}

ensure_oh_my_zsh() {
  require_command git "to install Oh My Zsh"

  # Fast path: an existing clean Oh My Zsh checkout is fast-forwarded in place.
  if oh_my_zsh_is_installed && [[ -z "$(git -C "${OH_MY_ZSH_DIR}" status --porcelain)" ]]; then
    log "Updating Oh My Zsh in ${OH_MY_ZSH_DIR}."
    if git -C "${OH_MY_ZSH_DIR}" fetch --quiet origin \
       && git -C "${OH_MY_ZSH_DIR}" merge --ff-only --quiet '@{u}'; then
      return
    fi
    log_warn "Could not fast-forward Oh My Zsh; reinstalling."
  fi

  # Anything else (missing, unmanaged changes, non-OMZ checkout, ff failure):
  # back up whatever is at the path and clone a fresh copy.
  if path_exists "${OH_MY_ZSH_DIR}"; then
    backup_path "${OH_MY_ZSH_DIR}"
  fi
  log "Installing Oh My Zsh into ${OH_MY_ZSH_DIR}."
  git clone --quiet --depth=1 "${OH_MY_ZSH_REPO}" "${OH_MY_ZSH_DIR}"
}

# Strip ${DOCKER_CASK} from the working Brewfile when Docker.app already exists
# outside Homebrew. Keeps bootstrap idempotent without editing the curated file.
prepare_brewfile() {
  WORK_BREWFILE="$(mktemp)"
  log "Preparing Brewfile from ${BREWFILE}."
  cp "${BREWFILE}" "${WORK_BREWFILE}"

  if [[ -d "${DOCKER_APP}" ]] && ! brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1; then
    log_warn "Skipping Docker cask because /Applications/Docker.app already exists outside Homebrew."
    grep -Ev "^[[:space:]]*cask[[:space:]]+[\"']${DOCKER_CASK}[\"'][[:space:]]*$" \
      "${WORK_BREWFILE}" > "${WORK_BREWFILE}.tmp"
    mv "${WORK_BREWFILE}.tmp" "${WORK_BREWFILE}"
  fi
}

verify_docker_desktop() {
  # Docker.app may come from Homebrew (fresh machine) or have been installed
  # manually before this repo was adopted. Either way it must be present.
  if brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1 || [[ -d "${DOCKER_APP}" ]]; then
    log_success "Verified Docker Desktop."
    return
  fi
  log_error "Docker Desktop was not installed. Re-run bootstrap or install the ${DOCKER_CASK} cask."
  exit 1
}

cleanup_workfile() {
  if [[ -n "${WORK_BREWFILE}" && -f "${WORK_BREWFILE}" ]]; then
    rm -f "${WORK_BREWFILE}"
  fi
}

main() {
  trap cleanup_workfile EXIT

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for macOS."

  ensure_xcode_clt
  ensure_homebrew

  prepare_brewfile
  log "Installing Homebrew packages and casks..."
  brew bundle --file "${WORK_BREWFILE}"
  verify_docker_desktop
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

  if ! oh_my_zsh_is_installed; then
    log_error "Oh My Zsh was not installed correctly: ${OH_MY_ZSH_DIR}"
    exit 1
  fi

  echo
  log_success "initd finished for macOS."
}

main "$@"
