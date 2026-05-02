#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"
WORK_BREWFILE=""

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    return
  fi

  echo "Xcode Command Line Tools are required. Launching installer..."
  xcode-select --install || true
  echo "Finish the Xcode Command Line Tools install, then re-run ./bootstrap.sh"
  exit 1
}

ensure_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_mise_trust() {
  if ! command -v mise >/dev/null 2>&1; then
    echo "mise is required but was not found after Homebrew install."
    exit 1
  fi

  mise trust "${ROOT_DIR}/mise.toml"
}

prepare_brewfile() {
  WORK_BREWFILE="$(mktemp)"
  cp "${BREWFILE}" "${WORK_BREWFILE}"

  if [[ -d /Applications/Docker.app ]] && ! brew list --cask docker >/dev/null 2>&1; then
    echo "Skipping Docker cask because /Applications/Docker.app already exists outside Homebrew."
    awk '$0 != "cask \"docker\""' "${WORK_BREWFILE}" > "${WORK_BREWFILE}.tmp"
    mv "${WORK_BREWFILE}.tmp" "${WORK_BREWFILE}"
  fi
}

cleanup() {
  if [[ -n "${WORK_BREWFILE}" && -f "${WORK_BREWFILE}" ]]; then
    rm -f "${WORK_BREWFILE}"
  fi
}

main() {
  trap cleanup EXIT

  ensure_xcode_clt
  ensure_homebrew
  prepare_brewfile

  if command -v mise >/dev/null 2>&1; then
    echo "Trusting shared mise config..."
    ensure_mise_trust
  fi

  echo "Installing macOS packages..."
  brew bundle --file "${WORK_BREWFILE}"

  echo "Trusting shared mise config..."
  ensure_mise_trust

  echo "Installing shared runtimes..."
  mise install --yes

  echo "Applying macOS defaults..."
  "${ROOT_DIR}/platforms/darwin/macos.sh"

  echo "Stowing managed configs..."
  "${ROOT_DIR}/scripts/stow.sh"

  echo
  echo "initd finished for macOS."
}

main "$@"
