#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"
MISE_CONFIG="${ROOT_DIR}/mise.toml"
MISE_GLOBAL_CONFIG="${HOME}/.config/mise/config.toml"
ZSHRC="${HOME}/.zshrc"
ZPROFILE="${HOME}/.zprofile"
MANAGED_ZSHRC="${ROOT_DIR}/zsh-home/.zshrc"
INITD_ZSH="${HOME}/.config/zsh/initd.zsh"
INITD_ZPROFILE="${HOME}/.config/zsh/initd.zprofile"
ZSHRC_SOURCE_LINE='[[ -f "${HOME}/.config/zsh/initd.zsh" ]] && source "${HOME}/.config/zsh/initd.zsh"'
ZPROFILE_SOURCE_LINE='[[ -f "${HOME}/.config/zsh/initd.zprofile" ]] && source "${HOME}/.config/zsh/initd.zprofile"'
WORK_BREWFILE=""

log() {
  echo "==> $*"
}

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
    echo "${command_name} is required ${context}."
    exit 1
  fi
}

verify_symlink_target() {
  local path="$1"
  local expected="$2"
  local label="$3"

  if [[ ! -L "${path}" ]]; then
    echo "${label} was not installed as a symlink: ${path}"
    exit 1
  fi

  if [[ "$(resolve_symlink_target "${path}")" != "${expected}" ]]; then
    echo "${label} points to the wrong target: ${path}"
    echo "Expected: ${expected}"
    echo "Resolved: $(resolve_symlink_target "${path}")"
    exit 1
  fi

  log "Verified ${label}."
}

git_profile_is_managed() {
  local path="${HOME}/.config/git/profile.gitconfig"
  local resolved=""

  if [[ ! -L "${path}" ]]; then
    return 1
  fi

  resolved="$(resolve_symlink_target "${path}")"

  case "${resolved}" in
    "${ROOT_DIR}/git/.config/git/profiles/"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

verify_profile_symlink() {
  local path="${HOME}/.config/git/profile.gitconfig"

  if ! git_profile_is_managed; then
    echo "git profile config points outside the managed profiles directory: ${path}"
    echo "Resolved: $(resolve_symlink_target "${path}" 2>/dev/null || echo missing)"
    exit 1
  fi

  log "Verified git profile config."
}

ensure_git_profile() {
  if git_profile_is_managed; then
    log "Git profile already configured."
    return
  fi

  log "Setting default git profile to personal."
  "${ROOT_DIR}/scripts/git-profile.sh" personal
}

zshrc_is_managed() {
  [[ -L "${ZSHRC}" ]] && [[ "$(resolve_symlink_target "${ZSHRC}")" == "${MANAGED_ZSHRC}" ]]
}

verify_zshrc() {
  if zshrc_is_managed; then
    log "Verified zshrc symlink."
    return
  fi

  if [[ -f "${ZSHRC}" ]] && grep -qxF "${ZSHRC_SOURCE_LINE}" "${ZSHRC}"; then
    log "Verified zshrc sourcing in existing file."
    return
  fi

  echo "zshrc is not managed correctly: ${ZSHRC}"
  exit 1
}

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log "Xcode Command Line Tools already installed."
    return
  fi

  echo "Xcode Command Line Tools are required. Launching installer..."
  xcode-select --install || true
  echo "Finish the Xcode Command Line Tools install, then re-run ./bootstrap.sh"
  exit 1
}

ensure_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found. Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    log "Homebrew already installed."
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  require_command brew "but was not found after Homebrew setup"
}

ensure_mise_trust() {
  if ! command -v mise >/dev/null 2>&1; then
    echo "mise is required but was not found after Homebrew install."
    exit 1
  fi

  log "Trusting ${MISE_CONFIG} in mise."
  mise trust "${MISE_CONFIG}"
}

sync_mise_config() {
  log "Linking ${MISE_GLOBAL_CONFIG} -> ${MISE_CONFIG}"
  mkdir -p "$(dirname "${MISE_GLOBAL_CONFIG}")"
  ln -snf "${MISE_CONFIG}" "${MISE_GLOBAL_CONFIG}"
}

ensure_line_in_file() {
  local file="$1"
  local line="$2"
  local label="$3"

  touch "${file}"

  if ! grep -qxF "${line}" "${file}"; then
    printf '\n%s\n' "${line}" >> "${file}"
    log "Added ${label} to ${file}."
  else
    log "${label} already present in ${file}."
  fi
}

ensure_zsh_startup() {
  if zshrc_is_managed; then
    log "Managed .zshrc symlink already installed."
  elif [[ ! -e "${ZSHRC}" ]]; then
    log "Linking managed .zshrc into ${HOME}."
    ln -snf "${MANAGED_ZSHRC}" "${ZSHRC}"
  else
    log ".zshrc already exists; preserving it and ensuring initd sourcing."
    ensure_line_in_file "${ZSHRC}" "${ZSHRC_SOURCE_LINE}" "initd zshrc sourcing"
  fi

  ensure_line_in_file "${ZPROFILE}" "${ZPROFILE_SOURCE_LINE}" "initd zprofile sourcing"
}

verify_managed_links() {
  log "Verifying managed links..."
  verify_symlink_target "${HOME}/.config/mise/config.toml" "${MISE_CONFIG}" "mise config"
  verify_symlink_target "${HOME}/.config/kitty" "${ROOT_DIR}/kitty/.config/kitty" "kitty config"
  verify_symlink_target "${HOME}/.config/nvim" "${ROOT_DIR}/nvim/.config/nvim" "nvim config"
  verify_symlink_target "${HOME}/.gitconfig" "${ROOT_DIR}/git/.gitconfig" "git config"
  verify_zshrc
  verify_profile_symlink
}

prepare_brewfile() {
  WORK_BREWFILE="$(mktemp)"
  log "Preparing Brewfile from ${BREWFILE}."
  cp "${BREWFILE}" "${WORK_BREWFILE}"

  if [[ -d /Applications/Docker.app ]] && ! brew list --cask docker-desktop >/dev/null 2>&1; then
    echo "Skipping Docker cask because /Applications/Docker.app already exists outside Homebrew."
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

  log "Starting initd bootstrap for macOS."
  ensure_xcode_clt
  ensure_homebrew
  prepare_brewfile

  log "Installing Homebrew packages and casks..."
  brew bundle --file "${WORK_BREWFILE}"
  require_command mise "after brew bundle"
  require_command stow "after brew bundle"

  log "Syncing global mise config..."
  sync_mise_config

  log "Ensuring shared mise config is trusted..."
  ensure_mise_trust

  log "Installing shared runtimes with mise..."
  (
    cd "${ROOT_DIR}"
    mise install --yes
  )

  log "Applying macOS defaults..."
  "${ROOT_DIR}/platforms/darwin/macos.sh"

  log "Stowing managed configs into ${HOME}..."
  "${ROOT_DIR}/scripts/stow.sh"

  log "Ensuring zsh startup files source initd snippets..."
  ensure_zsh_startup

  ensure_git_profile

  verify_managed_links

  echo
  log "initd finished for macOS."
}

main "$@"
