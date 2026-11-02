#!/usr/bin/env bash
set -euo pipefail

# Syncs the wallpapers from github.com/vishnukg/wallpapers straight into
# ~/.local/share/wallpapers, the path hyprpaper.conf and hyprlock.conf read the
# default wallpaper from. They used to be committed here under shared/wallpaper
# and linked into place; they are a separate repo now so initd stays small.
#
# Wallpapers are optional: every failure path warns and exits 0, so an offline
# machine still bootstraps (hyprpaper just shows no image). Re-run any time.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

# Never stop for a username/password: a git that cannot authenticate fails, and
# the paths below turn that into a warning.
export GIT_TERMINAL_PROMPT=0

WALLPAPERS_DIR="${HOME}/.local/share/wallpapers"
# SSH first, so the clone can push the way initd does; HTTPS (read-only, the
# repo is public) when SSH cannot authenticate. On a fresh machine it usually
# cannot yet: this runs before shared/lib/ssh-keys.sh writes the GitHub public
# key the SSH config names, a work machine has no GitHub key at all, and
# known_hosts may not hold github.com. A clone that fell back stays on HTTPS;
# switch it later with `git remote set-url origin <the SSH URL below>`.
WALLPAPERS_SSH_URL="git@github.com:vishnukg/wallpapers.git"
WALLPAPERS_URL="https://github.com/vishnukg/wallpapers.git"

main() {
  # The old MANAGED_LINKS entry pointed this path at initd's shared/wallpaper,
  # which no longer exists. That link is ours to replace; anything else is not.
  if [[ -L "${WALLPAPERS_DIR}" && "$(readlink "${WALLPAPERS_DIR}")" == */shared/wallpaper ]]; then
    log "Removing the old initd wallpaper link..."
    rm "${WALLPAPERS_DIR}"
  fi

  if [[ -d "${WALLPAPERS_DIR}/.git" ]]; then
    log "Updating wallpapers..."
    if git -C "${WALLPAPERS_DIR}" pull --ff-only --quiet; then
      log_success "Wallpapers up to date."
    else
      log_warn "Could not update ${WALLPAPERS_DIR} (offline?) — keeping existing wallpapers."
    fi
    return
  fi

  if [[ -e "${WALLPAPERS_DIR}" || -L "${WALLPAPERS_DIR}" ]]; then
    log_warn "${WALLPAPERS_DIR} exists but is not a git clone — skipping sync."
    return
  fi

  mkdir -p "$(dirname "${WALLPAPERS_DIR}")"
  # Shallow: the history is only images that are no longer used. BatchMode
  # makes ssh fail rather than ask (an unknown host key, a passphrase), which
  # GIT_TERMINAL_PROMPT does not cover; git removes a failed clone's directory,
  # so the HTTPS attempt starts clean.
  log "Cloning wallpapers (${WALLPAPERS_SSH_URL})..."
  if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" \
    git clone --depth 1 --quiet "${WALLPAPERS_SSH_URL}" "${WALLPAPERS_DIR}"; then
    log_success "Wallpapers cloned into ${WALLPAPERS_DIR}."
    return
  fi

  log_warn "SSH clone failed — falling back to HTTPS (${WALLPAPERS_URL})."
  if git clone --depth 1 --quiet "${WALLPAPERS_URL}" "${WALLPAPERS_DIR}"; then
    log_success "Wallpapers cloned into ${WALLPAPERS_DIR}."
  else
    log_warn "Could not clone ${WALLPAPERS_URL} — continuing without wallpapers."
  fi
}

main
