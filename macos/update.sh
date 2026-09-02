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
  brew bundle --file macos/Brewfile
  brew upgrade
  brew cleanup
  mise upgrade --yes
  fisher update (if installed)
  brew bundle cleanup (report only — lists installs the Brewfile doesn't own)

Options:
  -h, --help     Show this help.
EOF
}

ensure_homebrew_env() {
  if [[ ! -x /opt/homebrew/bin/brew ]]; then
    log_error "Homebrew is required at the Apple Silicon prefix /opt/homebrew. Run macos/bootstrap.sh first."
    exit 1
  fi

  eval "$(/opt/homebrew/bin/brew shellenv)"
}

main() {
  if [[ "$#" -gt 0 ]]; then
    case "$1" in
      -h|--help) usage; return ;;
      *) log_error "Unknown argument: $1"; usage >&2; exit 1 ;;
    esac
  fi

  ensure_homebrew_env

  log "Updating Homebrew metadata..."
  brew update

  log "Installing any new Brewfile entries..."
  brew bundle --file "${ROOT_DIR}/macos/Brewfile"

  log "Upgrading Homebrew formulae and casks..."
  brew upgrade

  log "Cleaning old Homebrew versions..."
  brew cleanup

  require_command mise "to upgrade mise-managed tools"
  log "Upgrading mise-managed tools..."
  mise upgrade --yes

  if command -v fish &>/dev/null && fish -c "type -q fisher" 2>/dev/null; then
    log "Updating fish plugins..."
    fish -c "fisher update"
  fi

  # Report only: surfaces packages installed outside the Brewfile so the machine
  # and the curated list don't silently drift. Apply with `--force` by hand.
  log "Checking for packages the Brewfile doesn't own..."
  brew bundle cleanup --file "${ROOT_DIR}/macos/Brewfile" || true

  log_success "Machine update complete."
}

main "$@"
