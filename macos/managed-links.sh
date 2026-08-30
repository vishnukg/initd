#!/usr/bin/env bash

# macOS-only managed symlinks. Appended to the shared MANAGED_LINKS array.
# Currently empty: every macOS dotfile is cross-platform.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing macos/managed-links.sh}"
: "${MANAGED_LINKS:?MANAGED_LINKS must be initialised by shared/managed-links.sh first}"

# Example future entry:
#   MANAGED_LINKS+=( "${HOME}/Library/Application Support/Foo:${ROOT_DIR}/macos/configs/foo" )

# NOTE: fonts (shared/fonts/) are deliberately NOT managed links on macOS —
# CoreText refuses to register a font reached through a symlink (directory or
# file; verified). macos/bootstrap.sh:ensure_local_fonts copies them instead.
