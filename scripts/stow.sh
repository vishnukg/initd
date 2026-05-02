#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES=(git kitty nvim)
STOW_FLAGS=(--restow --dir "${ROOT_DIR}" --target "${HOME}")

if [[ "${INITD_STOW_ADOPT:-0}" == "1" ]]; then
  STOW_FLAGS+=(--adopt)
fi

stow "${STOW_FLAGS[@]}" "${PACKAGES[@]}"
