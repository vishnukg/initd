#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

usage() {
  cat <<EOF
Usage: ${0##*/}

Update apt packages, mise-managed tools, and the active Firefox profile config.

Runs:
  sudo apt-get update
  sudo apt-get upgrade -y
  sudo apt-get autoremove -y
  mise self-update --yes
  mise upgrade --yes
  linux/setup.sh --firefox-only

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

  require_command apt-get "to update Debian packages"

  log "Refreshing apt package lists..."
  sudo apt-get update

  log "Upgrading apt packages..."
  sudo apt-get upgrade -y

  log "Removing obsolete packages..."
  sudo apt-get autoremove -y

  require_command mise "to update mise and its managed tools"
  log "Updating mise..."
  mise self-update --yes

  log "Upgrading mise-managed tools..."
  mise upgrade --yes

  log "Refreshing Firefox configuration..."
  "${ROOT_DIR}/linux/setup.sh" --firefox-only

  log_success "Machine update complete."
}

main "$@"
