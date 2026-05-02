#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES=(git kitty nvim shell)
STOW_FLAGS=(--restow --dir "${ROOT_DIR}" --target "${HOME}")
STOW_OUTPUT=""
VERIFY_WARNING="WARNING: in simulation mode so not modifying filesystem."

log() {
  echo "==> $*"
}

cleanup() {
  if [[ -n "${STOW_OUTPUT}" && -f "${STOW_OUTPUT}" ]]; then
    rm -f "${STOW_OUTPUT}"
  fi
}

verify_install() {
  local verify_output=""
  local verify_status=0
  local filtered_output=""

  verify_output="$(stow --simulate --verbose=1 --dir "${ROOT_DIR}" --target "${HOME}" "${PACKAGES[@]}" 2>&1)" || verify_status=$?
  filtered_output="$(printf '%s\n' "${verify_output}" | grep -vFx "${VERIFY_WARNING}" || true)"

  if (( verify_status != 0 )) || [[ -n "${filtered_output//[$'\n\r\t ']}" ]]; then
    echo "stow finished but the managed links are not fully installed yet." >&2

    if [[ -n "${filtered_output//[$'\n\r\t ']}" ]]; then
      printf '%s\n' "${filtered_output}" >&2
    fi

    exit 1
  fi

  log "Managed symlinks verified."
}

main() {
  trap cleanup EXIT
  STOW_OUTPUT="$(mktemp)"
  log "Stowing packages: ${PACKAGES[*]}"
  log "Target home directory: ${HOME}"

  if stow "${STOW_FLAGS[@]}" "${PACKAGES[@]}" 2> >(tee "${STOW_OUTPUT}" >&2); then
    verify_install
    return
  fi

  if grep -q "would cause conflicts" "${STOW_OUTPUT}"; then
    echo
    echo "Stow found existing files in ${HOME} that are not symlinks yet."
    echo "Remove or move the conflicting files, then re-run one of:"
    echo "  ~/.config/initd/scripts/stow.sh"
    echo "  bash ~/.config/initd/bootstrap.sh"
  else
    echo "stow failed before managed links were fully installed." >&2
  fi

  exit 1
}

main "$@"
