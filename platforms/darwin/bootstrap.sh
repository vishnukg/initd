#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"
MISE_CONFIG="${ROOT_DIR}/mise.toml"
MISE_GLOBAL_CONFIG="${HOME}/.config/mise/config.toml"
ZSHRC="${HOME}/.zshrc"
ZPROFILE="${HOME}/.zprofile"
INITD_ZSH="${HOME}/.config/zsh/initd.zsh"
INITD_ZPROFILE="${HOME}/.config/zsh/initd.zprofile"
WORK_BREWFILE=""

log() {
  echo "==> $*"
}

require_command() {
  local command_name="$1"
  local context="$2"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${command_name} is required ${context}."
    exit 1
  fi
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
  ensure_line_in_file "${ZPROFILE}" "[[ -f \"${INITD_ZPROFILE}\" ]] && source \"${INITD_ZPROFILE}\"" "initd zprofile sourcing"
  ensure_line_in_file "${ZSHRC}" "[[ -f \"${INITD_ZSH}\" ]] && source \"${INITD_ZSH}\"" "initd zshrc sourcing"
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

  if [[ ! -e "${HOME}/.config/git/profile.gitconfig" ]]; then
    log "Setting default git profile to personal."
    "${ROOT_DIR}/scripts/git-profile.sh" personal
  else
    log "Git profile already configured."
  fi

  echo
  log "initd finished for macOS."
}

main "$@"
