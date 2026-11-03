#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${ROOT_DIR}/shared/lib/logging.sh"
source "${ROOT_DIR}/macos/brewfile.sh"
BREWFILE="${ROOT_DIR}/macos/Brewfile"
brewfile_tmp=""

usage() {
  cat <<EOF
Usage: ${0##*/}

Update machine-managed tools outside the bootstrap path.

Runs:
  brew update
  brew bundle --file macos/Brewfile
  brew upgrade
  brew cleanup
  mise -C "${ROOT_DIR}" upgrade --yes
  node shared/lib/dotnet-prune.mjs   (removes .NET runtimes no SDK uses)
  fisher update (when fish and fisher are installed)
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

  brewfile_tmp="$(mktemp)"
  trap 'rm -f "${brewfile_tmp}" "${brewfile_tmp}.tmp"' EXIT
  prepare_brewfile

  log "Installing any new Brewfile entries..."
  # --no-upgrade: the brew upgrade below already upgrades everything once.
  brew bundle --no-upgrade --file "${brewfile_tmp}"

  log "Upgrading Homebrew formulae and casks..."
  brew upgrade

  log "Cleaning old Homebrew versions..."
  brew cleanup

  require_command mise "to upgrade mise-managed tools"
  log "Upgrading mise-managed tools..."
  mise -C "${ROOT_DIR}" upgrade --yes

  log "Pruning .NET runtimes the installed SDKs no longer use..."
  # mise removes an old SDK but not the runtimes, packs and templates it shared
  # the dotnet root with; see shared/lib/dotnet-prune.mjs. Not fatal.
  mise exec node@lts -- node "${ROOT_DIR}/shared/lib/dotnet-prune.mjs" \
    || log_warn ".NET prune failed; run shared/lib/dotnet-prune.mjs --dry-run to see why."

  if command -v fish >/dev/null 2>&1 && fish -c "type -q fisher" 2>/dev/null; then
    log "Updating fish plugins..."
    # fisher reads plugin names from a non-tty stdin; /dev/null keeps it from
    # waiting. The token lifts GitHub's 60-an-hour anonymous API limit. Not
    # fatal: a failed plugin fetch must not skip the steps after it.
    GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)" fish -c "fisher update" </dev/null \
      || log_warn "fisher update failed; re-run macos/update.sh or 'fisher update' later."
  fi

  # Report only: surfaces packages installed outside the Brewfile so the machine
  # and the curated list don't silently drift. Apply with `--force` by hand.
  log "Checking for packages the Brewfile doesn't own..."
  brew bundle cleanup --file "${ROOT_DIR}/macos/Brewfile" || true

  log_success "Machine update complete."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
