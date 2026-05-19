#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${ROOT_DIR}/shared/lib/logging.sh"

usage() {
  cat <<EOF
Usage: ${0##*/}

Update machine-managed tools outside the bootstrap path.

Runs:
  brew update
  brew upgrade
  brew cleanup
  mise upgrade --yes

Options:
  -h, --help     Show this help.
EOF
}

ensure_homebrew_env() {
  # Apple Silicon installs to /opt/homebrew; Intel to /usr/local.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  require_command brew "to update Homebrew packages"
}

main() {
  while (($#)); do
    case "$1" in
      -h|--help) usage; return ;;
      *) log_error "Unknown argument: $1"; usage >&2; exit 1 ;;
    esac
    shift
  done

  ensure_homebrew_env

  log "Updating Homebrew metadata..."
  brew update

  log "Upgrading Homebrew formulae and casks..."
  brew upgrade

  log "Cleaning old Homebrew versions..."
  brew cleanup

  require_command mise "to upgrade mise-managed tools"
  log "Upgrading mise-managed tools..."
  mise upgrade --yes

  log_success "Machine update complete."
}

main "$@"
