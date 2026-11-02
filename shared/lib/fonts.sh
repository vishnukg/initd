#!/usr/bin/env bash
set -euo pipefail

# Syncs licensed fonts from the PRIVATE github.com/vishnukg/fonts repo into
# shared/fonts/ (gitignored — this repo is public and must never carry the
# files itself). Run standalone or from a platform bootstrap, BEFORE link.sh:
# linux/managed-links.sh only appends its font link when the directory exists.
#
# Fonts are optional: every failure path here warns and exits 0 so a machine
# without gh auth (or without access to the private repo) still bootstraps.
# Re-run after `gh auth login` to pick the fonts up.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

# Never stop for a username/password: a git that cannot authenticate fails, and
# the paths below turn that into a warning.
export GIT_TERMINAL_PROMPT=0

FONTS_DIR="${ROOT_DIR}/shared/fonts"
FONTS_REPO="vishnukg/fonts"

main() {
  if [[ -d "${FONTS_DIR}/.git" ]]; then
    log "Updating fonts from private repo (${FONTS_REPO})..."
    # Credentials straight from gh: the helper `gh auth login` writes into a
    # fresh ~/.gitconfig is gone once link.sh swaps that file for the tracked
    # one, and this repo is private.
    if git -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
      -C "${FONTS_DIR}" pull --ff-only --quiet; then
      log_success "Fonts up to date."
    else
      log_warn "Could not update ${FONTS_DIR} (offline?) — keeping existing fonts."
    fi
    return
  fi

  if [[ -d "${FONTS_DIR}" ]]; then
    # Pre-private-repo layout, or hand-copied fonts: leave them alone.
    log_warn "${FONTS_DIR} exists but is not a git clone — skipping sync."
    return
  fi

  # gh auth token, the check the bootstraps use: gh auth status also fails on a
  # stale token for some other host or account.
  if ! command -v gh >/dev/null 2>&1 || ! gh auth token --hostname github.com >/dev/null 2>&1; then
    log_warn "gh is not authenticated — skipping private font sync."
    log_info "Run 'gh auth login', then shared/lib/fonts.sh to fetch fonts."
    return
  fi

  log "Cloning private fonts repo (${FONTS_REPO})..."
  if gh repo clone "${FONTS_REPO}" "${FONTS_DIR}" -- --quiet; then
    log_success "Fonts cloned into ${FONTS_DIR}."
  else
    log_warn "Could not clone ${FONTS_REPO} — continuing without licensed fonts."
  fi
}

main
