#!/usr/bin/env bash
# Install or upgrade hyprmoncfg from its upstream GitHub release rpm.
#
# Why not the paolino/hyprmoncfg COPR, which used to be the source: its last
# build is 1.17.0 (1 September 2026) while upstream kept releasing, and 1.20
# through 1.25 are the wake-recovery fixes for an external monitor that stays
# dark after DPMS display sleep (upstream issue #67: the daemon retries the
# wake, lights the laptop panel when no external shows a picture, verifies an
# enabled display actually woke and rolls back if not). That is the clamshell
# failure described in docs/linux-monitors.md. Upstream publishes an rpm with
# every release (PACKAGING.md), so this installs that one: the "latest"
# redirect resolves the version, packaging-checksums.txt verifies the file,
# and `dnf install` of the local rpm upgrades in place -- same package name,
# so the COPR build is replaced and dnf keeps owning the files.
#
# Run by linux/bootstrap.sh after the Hyprland packages (the rpm requires
# hyprland) and by linux/update.sh on every run. At the installed version it
# downloads nothing but the checksum file and installs nothing. Unreachable
# GitHub is a warning, never a failed bootstrap.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

RELEASE_BASE="${HYPRMONCFG_RELEASE_BASE:-https://github.com/crmne/hyprmoncfg/releases/latest/download}"
ARCH="${HYPRMONCFG_ARCH:-$(uname -m)}"

fetch() {
  curl -fsSL --max-time 120 -o "$2" "$1"
}

retire_copr() {
  # One source only. A machine that still has the COPR enabled would take
  # whichever build is newer on the next `dnf upgrade`, and the COPR's unit
  # also sat under /usr/lib64/systemd/user, where the user manager never looks.
  if dnf copr list 2>/dev/null | grep -qE '/paolino/hyprmoncfg( |$)'; then
    log "Removing the stale paolino/hyprmoncfg COPR (upstream rpm is the source now)..."
    sudo dnf -y copr remove paolino/hyprmoncfg || log_warn "Could not remove the paolino/hyprmoncfg COPR; remove it by hand."
  fi
}

# Global, not local to main: the EXIT trap runs after main has returned.
WORK=""
cleanup() { [[ -n "${WORK}" ]] && rm -rf "${WORK}"; }
trap cleanup EXIT

main() {
  require_command curl "to download hyprmoncfg releases"
  local work
  WORK="$(mktemp -d)"
  work="${WORK}"

  log "Checking the latest hyprmoncfg release..."
  if ! fetch "${RELEASE_BASE}/packaging-checksums.txt" "${work}/checksums"; then
    log_warn "Could not reach the hyprmoncfg release page; keeping the installed version."
    return 0
  fi
  local rpm_name
  rpm_name="$(grep -oE "hyprmoncfg-[0-9][^[:space:]]*\.${ARCH}\.rpm" "${work}/checksums" | head -n1 || true)"
  if [[ -z "${rpm_name}" ]]; then
    log_warn "The latest hyprmoncfg release has no ${ARCH} rpm; keeping the installed version."
    return 0
  fi

  local latest installed
  latest="${rpm_name#hyprmoncfg-}"
  latest="${latest%%-*}"
  installed="$(rpm -q --qf '%{VERSION}' hyprmoncfg 2>/dev/null || true)"
  if [[ "${installed}" == "${latest}" ]]; then
    log_success "hyprmoncfg ${latest} already installed."
    retire_copr
    return 0
  fi

  log "Installing hyprmoncfg ${latest} (installed: ${installed:-none})..."
  fetch "${RELEASE_BASE}/${rpm_name}" "${work}/${rpm_name}"
  # sha256sum -c reads "<hash>  <file>" lines and resolves the file relative
  # to the working directory, hence the cd.
  (cd "${work}" && grep -E "[[:space:]]${rpm_name}\$" checksums | sha256sum -c --quiet -)
  sudo dnf install -y "${work}/${rpm_name}"
  retire_copr
  # Upstream's upgrade note: restart the daemon so the new binary runs. Only
  # when a session has it running -- bootstrap from a TTY has none.
  if systemctl --user is-active --quiet hyprmoncfgd.service 2>/dev/null; then
    systemctl --user daemon-reload
    systemctl --user restart hyprmoncfgd.service
  fi
  log_success "hyprmoncfg ${latest} installed."
}

main "$@"
