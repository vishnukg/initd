#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

source "${ROOT_DIR}/scripts/logging.sh"

log "Detected operating system: ${OS}"

case "${OS}" in
  Darwin)
    log "Starting macOS bootstrap..."
    exec "${ROOT_DIR}/platforms/darwin/bootstrap.sh"
    ;;
  Linux)
    log_warn "Linux support is planned but not implemented yet."
    exit 1
    ;;
  *)
    log_error "Unsupported operating system: ${OS}"
    exit 1
    ;;
esac
