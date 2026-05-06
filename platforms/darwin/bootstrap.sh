#!/usr/bin/env bash
set -euo pipefail

# This script lives in platforms/darwin, so ../.. is the repository root.
# Using an absolute ROOT_DIR lets bootstrap be run from any directory.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Derived paths: keep source files in the repo, then point tools at them.
BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"
MISE_CONFIG="${ROOT_DIR}/mise/.config/mise/config.toml"
DOCKER_CASK="docker-desktop"
DOCKER_APP="/Applications/Docker.app"
OH_MY_ZSH_DIR="${HOME}/.oh-my-zsh"
OH_MY_ZSH_REPO="https://github.com/ohmyzsh/ohmyzsh.git"

# One timestamp per run keeps all preserved user files grouped together.
BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)"
WORK_BREWFILE=""

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"
source "${ROOT_DIR}/scripts/paths.sh"

require_command() {
  local command_name="$1"
  local context="$2"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log_error "${command_name} is required ${context}."
    exit 1
  fi
}

verify_path_missing() {
  local path="$1"
  local label="$2"

  if path_exists "${path}"; then
    log_error "${label} should not exist: ${path}"
    exit 1
  fi

  log_success "Verified ${label} is absent."
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
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found. Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    log_success "Homebrew already installed."
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

oh_my_zsh_is_installed() {
  local remote=""

  # A directory named ~/.oh-my-zsh is not enough; it must be an upstream Oh My
  # Zsh checkout so bootstrap can update or replace it predictably.
  if [[ ! -d "${OH_MY_ZSH_DIR}/.git" ]]; then
    return 1
  fi

  remote="$(git -C "${OH_MY_ZSH_DIR}" remote get-url origin 2>/dev/null || true)"

  case "${remote}" in
    "${OH_MY_ZSH_REPO}"|"git@github.com:ohmyzsh/ohmyzsh.git")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_oh_my_zsh() {
  require_command git "to install Oh My Zsh"

  if oh_my_zsh_is_installed; then
    # Local plugin/theme edits make an in-place update risky. Back up the whole
    # checkout and clone fresh so the final shell framework is known-good.
    if [[ -n "$(git -C "${OH_MY_ZSH_DIR}" status --porcelain)" ]]; then
      log "Existing Oh My Zsh checkout has unmanaged changes."
      backup_path "${OH_MY_ZSH_DIR}"
    else
      log "Updating Oh My Zsh in ${OH_MY_ZSH_DIR}."
      if ! git -C "${OH_MY_ZSH_DIR}" fetch --quiet origin; then
        log_error "Could not fetch Oh My Zsh updates. Check your network and re-run bootstrap."
        exit 1
      fi

      if git -C "${OH_MY_ZSH_DIR}" merge --ff-only --quiet '@{u}'; then
        return
      fi

      log "Existing Oh My Zsh checkout could not be fast-forwarded."
      backup_path "${OH_MY_ZSH_DIR}"
    fi
  else
    backup_path "${OH_MY_ZSH_DIR}"
  fi

  if [[ ! -d "${OH_MY_ZSH_DIR}" ]]; then
    log "Installing Oh My Zsh into ${OH_MY_ZSH_DIR}."
    git clone --quiet --depth=1 "${OH_MY_ZSH_REPO}" "${OH_MY_ZSH_DIR}"
  fi
}

ensure_mise_trust() {
  if ! command -v mise >/dev/null 2>&1; then
    log_error "mise is required but was not found after Homebrew install."
    exit 1
  fi

  log "Trusting ${MISE_CONFIG} in mise."
  mise trust "${MISE_CONFIG}"
}

verify_docker_desktop() {
  # The Brewfile installs Docker Desktop on fresh machines. If Docker.app already
  # existed before bootstrap, prepare_brewfile may skip the cask to avoid a
  # Homebrew conflict; either case should leave Docker available on the machine.
  if brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1 || [[ -d "${DOCKER_APP}" ]]; then
    log_success "Verified Docker Desktop."
    return
  fi

  log_error "Docker Desktop was not installed. Re-run bootstrap or install the ${DOCKER_CASK} cask."
  exit 1
}

  verify_managed_links() {
  local link=""

  # Bootstrap finishes only after checking the important user-visible paths. This
  # catches partial link runs or legacy paths that would otherwise fail later.
  log "Verifying managed links..."
  verify_path_missing "${HOME}/.config/git" "legacy git config directory"
  for link in "${MANAGED_LINKS[@]}"; do
    verify_symlink_target "${link%%:*}" "${link#*:}" "${link%%:*}"
  done
  if ! oh_my_zsh_is_installed; then
    log_error "Oh My Zsh was not installed correctly: ${OH_MY_ZSH_DIR}"
    exit 1
  fi
  log_success "Verified Oh My Zsh."
  verify_git_profile_link "${HOME}/.gitconfig" "git profile config"
}

prepare_brewfile() {
  WORK_BREWFILE="$(mktemp)"
  log "Preparing Brewfile from ${BREWFILE}."
  cp "${BREWFILE}" "${WORK_BREWFILE}"

  # Docker is commonly installed manually before this repo is adopted. Removing
  # just this cask from the temporary Brewfile keeps bootstrap idempotent without
  # changing the curated source Brewfile.
  if [[ -d "${DOCKER_APP}" ]] && ! brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1; then
    log_warn "Skipping Docker cask because /Applications/Docker.app already exists outside Homebrew."
    awk -v cask="${DOCKER_CASK}" '$0 != "cask \"" cask "\""' "${WORK_BREWFILE}" > "${WORK_BREWFILE}.tmp"
    mv "${WORK_BREWFILE}.tmp" "${WORK_BREWFILE}"
  else
    log "Using Brewfile as-is."
  fi
}

cleanup() {
  if [[ -n "${WORK_BREWFILE}" && -f "${WORK_BREWFILE}" ]]; then
    rm -f "${WORK_BREWFILE}"
  fi
}

main() {
  trap cleanup EXIT

  # Keep this flow as a high-level checklist; detailed migration and safety logic
  # lives in helper functions or scripts.
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

  log "Ensuring shared mise config is trusted..."
  ensure_mise_trust

  log "Installing shared runtimes with mise..."
  (
    cd "${ROOT_DIR}"
    mise install --yes
  )

  log "Applying macOS defaults..."
  "${ROOT_DIR}/platforms/darwin/macos.sh"

  verify_managed_links

  echo
  log_success "initd finished for macOS."
}

main "$@"
