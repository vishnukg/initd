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
  node shared/lib/dotnet-prune.mjs   (removes .NET runtimes no SDK uses)
  fisher update (when fish and fisher are installed)

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
  sudo apt-get -o DPkg::Lock::Timeout=300 update -q
  # confdef/confold: keep a locally edited config file (sshd_config, say)
  # instead of stopping at dpkg's "keep or replace?" prompt.
  sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade -y -q

  log "Removing obsolete packages..."
  sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 autoremove -y -q

  require_command mise "to update mise and its managed tools"
  log "Updating mise..."
  mise self-update --yes

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
    # waiting. The token lifts GitHub's 60-an-hour anonymous API limit, as in
    # vm/bootstrap.sh. Not fatal: a failed plugin fetch must not fail the run.
    GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)" fish -c "fisher update" </dev/null \
      || log_warn "fisher update failed; re-run vm/update.sh or 'fisher update' later."
  fi

  log_success "Machine update complete."
}

main "$@"
