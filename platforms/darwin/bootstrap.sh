#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"
MISE_CONFIG="${ROOT_DIR}/mise/.config/mise/config.toml"
OH_MY_ZSH_DIR="${HOME}/.oh-my-zsh"
OH_MY_ZSH_REPO="https://github.com/ohmyzsh/ohmyzsh.git"
ZSHRC="${HOME}/.zshrc"
ZPROFILE="${HOME}/.zprofile"
MANAGED_ZSHRC="${ROOT_DIR}/zsh/.zshrc"
MANAGED_ZPROFILE="${ROOT_DIR}/zsh/.zprofile"
BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)"
WORK_BREWFILE=""

source "${ROOT_DIR}/scripts/logging.sh"

resolve_symlink_target() {
  local path="$1"
  local target=""

  target="$(readlink "${path}")"

  if [[ "${target}" = /* ]]; then
    printf '%s\n' "${target}"
    return
  fi

  (
    cd "$(dirname "${path}")"
    cd "$(dirname "${target}")"
    printf '%s/%s\n' "$(pwd -P)" "$(basename "${target}")"
  )
}

require_command() {
  local command_name="$1"
  local context="$2"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log_error "${command_name} is required ${context}."
    exit 1
  fi
}

backup_path() {
  local path="$1"
  local relative="${path#"${HOME}/"}"
  local backup="${BACKUP_ROOT}/${relative}"

  if [[ ! -e "${path}" && ! -L "${path}" ]]; then
    return
  fi

  mkdir -p "$(dirname "${backup}")"
  log_warn "Backing up unmanaged ${path} -> ${backup}"
  mv "${path}" "${backup}"
}

verify_symlink_target() {
  local path="$1"
  local expected="$2"
  local label="$3"

  if [[ ! -L "${path}" ]]; then
    log_error "${label} was not installed as a symlink: ${path}"
    exit 1
  fi

  if [[ "$(resolve_symlink_target "${path}")" != "${expected}" ]]; then
    log_error "${label} points to the wrong target: ${path}"
    log_info "Expected: ${expected}"
    log_info "Resolved: $(resolve_symlink_target "${path}")"
    exit 1
  fi

  log_success "Verified ${label}."
}

verify_path_missing() {
  local path="$1"
  local label="$2"

  if [[ -e "${path}" || -L "${path}" ]]; then
    log_error "${label} should not exist: ${path}"
    exit 1
  fi

  log_success "Verified ${label} is absent."
}

git_profile_is_managed() {
  local path="${ROOT_DIR}/git/profile.gitconfig"
  local resolved=""

  if [[ ! -L "${path}" ]]; then
    return 1
  fi

  resolved="$(resolve_symlink_target "${path}")"

  case "${resolved}" in
    "${ROOT_DIR}/git/profiles/"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

verify_profile_symlink() {
  local path="${ROOT_DIR}/git/profile.gitconfig"

  if ! git_profile_is_managed; then
    log_error "git profile config points outside the managed profiles directory: ${path}"
    log_info "Resolved: $(resolve_symlink_target "${path}" 2>/dev/null || echo missing)"
    exit 1
  fi

  log_success "Verified git profile config."
}

ensure_git_profile() {
  if git_profile_is_managed; then
    log "Git profile already configured."
    return
  fi

  log "Setting default git profile to personal."
  "${ROOT_DIR}/scripts/git-profile.sh" personal
}

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log_success "Xcode Command Line Tools already installed."
    return
  fi

  log_warn "Xcode Command Line Tools are required. Launching installer..."
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

verify_managed_links() {
  log "Verifying managed links..."
  verify_symlink_target "${HOME}/.config/mise" "${ROOT_DIR}/mise/.config/mise" "mise config directory"
  verify_symlink_target "${HOME}/.gitconfig" "${ROOT_DIR}/git/.gitconfig" "home gitconfig"
  verify_path_missing "${HOME}/.config/git" "legacy git config directory"
  verify_symlink_target "${HOME}/.config/kitty" "${ROOT_DIR}/kitty/.config/kitty" "kitty config directory"
  verify_symlink_target "${HOME}/.config/nvim" "${ROOT_DIR}/nvim/.config/nvim" "nvim config directory"
  verify_symlink_target "${ZSHRC}" "${MANAGED_ZSHRC}" "zshrc"
  verify_symlink_target "${ZPROFILE}" "${MANAGED_ZPROFILE}" "zprofile"
  if ! oh_my_zsh_is_installed; then
    log_error "Oh My Zsh was not installed correctly: ${OH_MY_ZSH_DIR}"
    exit 1
  fi
  log_success "Verified Oh My Zsh."
  verify_profile_symlink
}

prepare_brewfile() {
  WORK_BREWFILE="$(mktemp)"
  log "Preparing Brewfile from ${BREWFILE}."
  cp "${BREWFILE}" "${WORK_BREWFILE}"

  if [[ -d /Applications/Docker.app ]] && ! brew list --cask docker-desktop >/dev/null 2>&1; then
    log_warn "Skipping Docker cask because /Applications/Docker.app already exists outside Homebrew."
    awk '$0 != "cask \"docker-desktop\""' "${WORK_BREWFILE}" > "${WORK_BREWFILE}.tmp"
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

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for macOS."
  ensure_xcode_clt
  ensure_homebrew
  prepare_brewfile

  log "Installing Homebrew packages and casks..."
  brew bundle --file "${WORK_BREWFILE}"
  require_command mise "after brew bundle"
  require_command stow "after brew bundle"

  log "Ensuring Oh My Zsh is installed..."
  ensure_oh_my_zsh

  log "Stowing managed configs into ${HOME}..."
  "${ROOT_DIR}/scripts/stow.sh"

  log "Ensuring shared mise config is trusted..."
  ensure_mise_trust

  log "Installing shared runtimes with mise..."
  (
    cd "${ROOT_DIR}"
    mise install --yes
  )

  log "Applying macOS defaults..."
  "${ROOT_DIR}/platforms/darwin/macos.sh"

  ensure_git_profile

  verify_managed_links

  echo
  log_success "initd finished for macOS."
}

main "$@"
