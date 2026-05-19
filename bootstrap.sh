#!/usr/bin/env bash
set -euo pipefail

# Top-level dispatcher: detects the OS and hands off to the platform bootstrap.
# Each platform directory is self-contained — delete one without touching the other.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Darwin) exec "${ROOT_DIR}/macos/bootstrap.sh" "$@" ;;
  Linux)  exec "${ROOT_DIR}/linux/bootstrap.sh" "$@" ;;
  *)
    printf 'Unsupported OS: %s. initd supports macOS (Darwin) and Linux.\n' "$(uname -s)" >&2
    exit 1
    ;;
esac
