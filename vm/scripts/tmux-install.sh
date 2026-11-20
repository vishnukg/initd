#!/usr/bin/env bash
# Install or upgrade tmux from the tmux project's own release builds
# (github.com/tmux/tmux-builds: one static binary per platform).
#
# Why not apt: Ubuntu 24.04 ships tmux 3.4, and the shared tmux.conf is written
# against 3.8. The gap that matters on a box that mostly runs agents: only tmux
# 3.7+ honours an application's synchronized output (DECSET 2026), which is
# what stops Claude Code tearing and flickering inside a pane, and 3.5 reworked
# extended keys. apt's tmux stays in packages.txt as the fallback, so a box
# where this could not run still lands in a tmux.
#
# Why not mise, which lists the same builds: mise's shims are first on PATH,
# and a shim costs ~34 ms a call against ~2 ms direct (measured on the box).
# The status watcher calls tmux every second and the agent hooks on every tool
# call. So the binary goes straight to ~/.local/bin, which sits ahead of /bin
# on every PATH the box uses, a non-interactive ssh command included.
#
# Run by vm/update.sh, so by every bootstrap too. At the installed version it
# makes one API call and downloads nothing. A release younger than eight hours
# waits, like mise's minimum_release_age. No gh sign-in or no network is a
# warning, never a failed update.
#
# A running tmux server keeps the binary it started with: `tmux kill-server`
# (which ends its sessions), then reconnect, to move it to the new one.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

DEST="${HOME}/.local/bin/tmux"
MINIMUM_RELEASE_AGE=$((8 * 3600))
ARCH="${INITD_TMUX_ARCH:-$(uname -m)}"

# Global, not local to main: the EXIT trap runs after main has returned.
# `-z ||`, not `-n &&`: most runs never create WORK, and a false test as the
# trap's last command would become the script's exit status under set -e.
WORK=""
cleanup() { [[ -z "${WORK}" ]] || rm -rf "${WORK}"; }
trap cleanup EXIT

warn_running_server() {
  local running
  running="$("${DEST}" display-message -p '#{version}' 2>/dev/null || true)"
  if [[ -n "${running}" && "${running}" != "$1" ]]; then
    log_warn "The running tmux server is still ${running}. To switch: tmux kill-server (ends its sessions), then reconnect."
  fi
}

main() {
  require_command gh "to look up the latest tmux release"
  require_command curl "to download tmux"

  case "${ARCH}" in
    x86_64) ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) log_warn "tmux-builds has no linux-${ARCH} build; keeping the installed tmux."; return 0 ;;
  esac

  # One row: tag, age in seconds, sha256 digest, download URL. gh's own jq does
  # the JSON work, so nothing here parses it. A missing digest becomes "none":
  # an empty field would vanish, since read folds neighbouring tabs into one.
  log "Checking the latest tmux release..."
  local release
  release="$(gh api repos/tmux/tmux-builds/releases/latest --jq '
    .tag_name as $tag
    | (now - (.published_at | fromdateiso8601) | floor) as $age
    | .assets[]
    | select(.name == "tmux-\($tag | ltrimstr("v"))-linux-'"${ARCH}"'.tar.gz")
    | [$tag, $age, (.digest // "none"), .browser_download_url] | @tsv' 2>/dev/null || true)"
  if [[ -z "${release}" ]]; then
    log_warn "Could not read the tmux release (gh not signed in, or GitHub unreachable); keeping the installed tmux."
    return 0
  fi

  local tag age digest url latest installed
  IFS=$'\t' read -r tag age digest url <<< "${release}"
  latest="${tag#v}"
  installed="$("${DEST}" -V 2>/dev/null | awk '{print $2}' || true)"
  if [[ "${installed}" == "${latest}" ]]; then
    log_success "tmux ${latest} already installed."
    warn_running_server "${latest}"
    return 0
  fi
  # No apostrophe inside a ${var:-default}: bash pairs it with the next one,
  # lines away, and everything between - once, the digest check - is skipped.
  if [[ "${age}" -lt "${MINIMUM_RELEASE_AGE}" ]]; then
    log_info "tmux ${latest} was released under 8 hours ago; waiting, as mise does. Keeping ${installed:-the apt tmux}."
    return 0
  fi
  if [[ "${digest}" != sha256:* ]]; then
    log_warn "The tmux ${latest} release carries no sha256 digest; keeping ${installed:-the apt tmux}."
    return 0
  fi

  log "Installing tmux ${latest} (installed: ${installed:-none})..."
  WORK="$(mktemp -d)"
  curl -fsSL --max-time 120 -o "${WORK}/tmux.tar.gz" "${url}"
  printf '%s  %s\n' "${digest#sha256:}" "${WORK}/tmux.tar.gz" | sha256sum -c --quiet -
  tar -xzf "${WORK}/tmux.tar.gz" -C "${WORK}" tmux
  mkdir -p "$(dirname "${DEST}")"
  # Renamed into place, never written over: a running server has the old file
  # mapped, and writing to a running binary fails with "Text file busy".
  install -m 755 "${WORK}/tmux" "${DEST}.new"
  mv -f "${DEST}.new" "${DEST}"
  log_success "tmux ${latest} installed to ${DEST}."
  warn_running_server "${latest}"
}

main "$@"
