#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-personal}"
SOURCE="${ROOT_DIR}/git/.config/git/profiles/${PROFILE}.gitconfig"
TARGET="${HOME}/.config/git/profile.gitconfig"

log() {
  echo "==> $*"
}

if [[ ! -f "${SOURCE}" ]]; then
  echo "Unknown git profile: ${PROFILE}"
  echo "Available profiles: personal, work"
  exit 1
fi

log "Linking git profile ${PROFILE}."
mkdir -p "$(dirname "${TARGET}")"
ln -snf "${SOURCE}" "${TARGET}"
log "Active git profile: ${PROFILE}"
