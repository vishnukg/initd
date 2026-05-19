#!/usr/bin/env bash

# macOS-only managed symlinks. Appended to the shared MANAGED_LINKS array.
# Currently empty: every macOS dotfile is cross-platform.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing macos/managed-links.sh}"
: "${MANAGED_LINKS:?MANAGED_LINKS must be initialised by shared/managed-links.sh first}"

# Example future entry:
#   MANAGED_LINKS+=( "${HOME}/Library/Application Support/Foo:${ROOT_DIR}/macos/configs/foo" )
