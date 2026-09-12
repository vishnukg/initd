#!/usr/bin/env bash
set -euo pipefail

# Bootstrap installs mise before reaching this step; Node can be installed on
# demand even before the managed config symlinks exist.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec mise -C "${ROOT_DIR}" exec node@lts -- node "${ROOT_DIR}/shared/lib/link.mjs" "$@"
