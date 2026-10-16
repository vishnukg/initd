#!/usr/bin/env bash
set -euo pipefail

# Top-level dispatcher: hands off to the platform bootstrap named on the
# command line, or detects one from the OS when none is given. Each platform
# directory is self-contained — delete one without touching the others.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: ${0##*/} [macos|linux|vm]

  macos   macOS on Apple Silicon (alias: mac)
  linux   Fedora Workstation desktop (Hyprland)
  vm      headless Ubuntu dev box, e.g. exe.dev

With no platform, macOS runs macos and Linux runs linux. A headless Ubuntu
VM must be named: both are Linux, so the OS alone can't tell them apart.
EOF
}

main() {
  local os target expected
  os="$(uname -s)"

  case "${1:-}" in
    -h|--help) usage; return ;;
    macos|mac) target=macos; expected=Darwin ;;
    linux) target=linux; expected=Linux ;;
    vm) target=vm; expected=Linux ;;
    "")
      case "${os}" in
        Darwin) target=macos ;;
        Linux) target=linux ;;
        *)
          printf 'Unsupported OS: %s. initd supports macOS (Darwin) and Linux.\n' "${os}" >&2
          exit 1
          ;;
      esac
      expected="${os}"
      ;;
    *)
      printf 'Unknown platform: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac

  # Catch the obvious mix-up before any installs: running the macOS bootstrap
  # on Linux, or a Linux one on a Mac. Fedora vs Ubuntu is checked by the
  # platform bootstraps themselves (ensure_fedora / ensure_ubuntu).
  if [[ "${os}" != "${expected}" ]]; then
    printf "'%s' needs %s, but this machine is %s.\n" "${target}" "${expected}" "${os}" >&2
    exit 1
  fi

  exec "${ROOT_DIR}/${target}/bootstrap.sh"
}

main "$@"
