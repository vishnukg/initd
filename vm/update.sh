#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

usage() {
  cat <<EOF
Usage: ${0##*/}

Update apt packages and mise-managed tools on a headless VM.

Runs:
  sudo apt-get update && sudo apt-get full-upgrade -y
  sudo apt-get autoremove -y
  mise self-update --yes
  mise -C "${ROOT_DIR}" upgrade --yes

Options:
  -h, --help     Show this help.
EOF
}

main() {
  if [[ "$#" -gt 0 ]]; then
    case "$1" in
      -h|--help) usage; return ;;
      *) log_error "Unknown argument: $1"; usage >&2; exit 1 ;;
    esac
  fi

  require_command apt-get "to update Ubuntu packages"

  log "Upgrading apt packages..."
  sudo apt-get update -q
  sudo env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -q

  log "Removing obsolete packages..."
  sudo apt-get autoremove -y -q

  require_command mise "to update mise and its managed tools"
  log "Updating mise..."
  mise self-update --yes

  log "Upgrading mise-managed tools..."
  mise -C "${ROOT_DIR}" upgrade --yes

  log_success "Machine update complete."
}

main "$@"
