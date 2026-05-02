#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES=(git kitty nvim shell)
STOW_FLAGS=(--restow --dir "${ROOT_DIR}" --target "${HOME}")
STOW_OUTPUT=""

cleanup() {
  if [[ -n "${STOW_OUTPUT}" && -f "${STOW_OUTPUT}" ]]; then
    rm -f "${STOW_OUTPUT}"
  fi
}

main() {
  trap cleanup EXIT
  STOW_OUTPUT="$(mktemp)"

  if stow "${STOW_FLAGS[@]}" "${PACKAGES[@]}" 2> >(tee "${STOW_OUTPUT}" >&2); then
    return
  fi

  if grep -q "would cause conflicts" "${STOW_OUTPUT}"; then
    echo
    echo "Stow found existing files in ${HOME} that are not symlinks yet."
    echo "Remove or move the conflicting files, then re-run:"
    echo "  bash ~/.config/initd/bootstrap.sh"
  fi

  exit 1
}

main "$@"
