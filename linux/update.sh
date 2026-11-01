#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

usage() {
  cat <<EOF
Usage: ${0##*/}

Update dnf packages, mise-managed tools, and the active Firefox profile config.

Runs:
  sudo dnf upgrade --refresh -y
  sudo dnf autoremove -y
  sudo fwupdmgr refresh / update   (firmware; never reboots, only stages)
  mise self-update --yes
  mise -C "${ROOT_DIR}" upgrade --yes
  linux/setup.sh --firefox-only
  linux/scripts/wallpapers.sh

Options:
  -h, --help     Show this help.
EOF
}

update_firmware() {
  # BIOS, SSD, dock and Thunderbolt firmware via LVFS. sudo, not polkit: the
  # dnf steps above already cached credentials, so no GUI prompt pops up.
  # --no-reboot-check matters: --assume-yes alone also answers "yes" to
  # fwupdmgr's restart-now prompt, so a UEFI capsule update would reboot the
  # machine mid-script. Without it the capsule is staged for the next boot.
  # fwupdmgr exits 2 for "nothing to do" (metadata fresh, no updates).
  if ! command -v fwupdmgr >/dev/null 2>&1; then
    log_warn "fwupdmgr not found; skipping firmware updates."
    return
  fi
  log "Checking firmware updates..."
  local status=0
  sudo fwupdmgr refresh >/dev/null 2>&1 || status=$?
  [[ "${status}" == 0 || "${status}" == 2 ]] || log_warn "Firmware metadata refresh failed (exit ${status}); using cached metadata."
  status=0
  sudo fwupdmgr update --assume-yes --no-reboot-check --no-unreported-check || status=$?
  case "${status}" in
    0) log_success "Firmware updated. A pending UEFI update applies on the next reboot." ;;
    2) log_success "Firmware already up to date." ;;
    *) log_warn "Firmware update failed (exit ${status}); see fwupdmgr get-updates." ;;
  esac
}

main() {
  if [[ "$#" -gt 0 ]]; then
    case "$1" in
      -h|--help) usage; return ;;
      *) log_error "Unknown argument: $1"; usage >&2; exit 1 ;;
    esac
  fi

  require_command dnf "to update Fedora packages"

  log "Upgrading dnf packages..."
  sudo dnf upgrade --refresh -y

  log "Removing obsolete packages..."
  sudo dnf autoremove -y

  update_firmware

  require_command mise "to update mise and its managed tools"
  log "Updating mise..."
  mise self-update --yes

  log "Upgrading mise-managed tools..."
  mise -C "${ROOT_DIR}" upgrade --yes

  log "Updating wallpapers..."
  "${ROOT_DIR}/linux/scripts/wallpapers.sh"

  log "Refreshing Firefox configuration..."
  "${ROOT_DIR}/linux/setup.sh" --firefox-only

  log_success "Machine update complete."
}

main "$@"
