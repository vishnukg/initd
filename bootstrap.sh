#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Darwin)
    exec "${ROOT_DIR}/platforms/darwin/bootstrap.sh"
    ;;
  Linux)
    echo "Linux support is planned but not implemented yet."
    exit 1
    ;;
  *)
    echo "Unsupported operating system: $(uname -s)"
    exit 1
    ;;
esac
