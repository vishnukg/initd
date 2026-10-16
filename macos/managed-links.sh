#!/usr/bin/env bash

# macOS-only managed symlinks. Appended to the shared MANAGED_LINKS array.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing macos/managed-links.sh}"
: "${MANAGED_LINKS:?MANAGED_LINKS must be initialised by shared/managed-links.sh first}"

# Commit signing through 1Password, personal machines only - the same gate as
# the SSH config, read off the list shared/managed-links.sh just built rather
# than a second copy of its email check. The shared gitconfig includes this
# path; on a work machine it is never linked, so git skips the include.
if [[ " ${MANAGED_LINKS[*]} " == *" ${HOME}/.ssh/config:"* ]]; then
  MANAGED_LINKS+=(
    "${HOME}/.config/git/signing.gitconfig:${ROOT_DIR}/macos/configs/git/signing.gitconfig"
  )
fi

# NOTE: fonts (shared/fonts/) are deliberately NOT managed links on macOS —
# CoreText refuses to register a font reached through a symlink (directory or
# file; verified). macos/bootstrap.sh:ensure_local_fonts copies them instead.
