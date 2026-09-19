#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

export INITD_TEST_TMUX="${INITD_TEST_TMUX:-1}"
exec node --test "$@" tests/macos/*.test.mjs tests/shared/*.test.mjs
