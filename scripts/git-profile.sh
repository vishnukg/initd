#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-personal}"
SOURCE="${ROOT_DIR}/git/profiles/${PROFILE}.gitconfig"
TARGET="${ROOT_DIR}/git/profile.gitconfig"

log() {
  echo "==> $*"
}

if [[ ! -f "${SOURCE}" ]]; then
  echo "Unknown git profile: ${PROFILE}"
  echo "Available profiles: personal, work"
  exit 1
fi

log "Linking git profile ${PROFILE}."
(
  cd "$(dirname "${TARGET}")"
  ln -snf "profiles/${PROFILE}.gitconfig" "$(basename "${TARGET}")"
)
log "Active git profile: ${PROFILE}"
