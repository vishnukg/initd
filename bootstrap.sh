#!/usr/bin/env bash
set -euo pipefail

# BASH_SOURCE[0] is this script. dirname gives its folder, and pwd turns that
# into an absolute repo path so the script works from any current directory.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

# Keep the top-level entrypoint small: it only detects the host OS, then hands off
# to a platform-specific bootstrap that can manage its own dependencies.
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
