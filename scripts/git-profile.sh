#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-personal}"
SOURCE="${ROOT_DIR}/git/profiles/${PROFILE}.gitconfig"
TARGET="${ROOT_DIR}/git/profile.gitconfig"

source "${ROOT_DIR}/scripts/logging.sh"

if [[ ! -f "${SOURCE}" ]]; then
  log_error "Unknown git profile: ${PROFILE}"
  log_info "Available profiles: personal, work"
  exit 1
fi

# profile.gitconfig is intentionally a repo-local symlink so ~/.gitconfig can
# include one stable path while this script switches between named profiles.
log "Linking git profile ${PROFILE}."
(
  cd "$(dirname "${TARGET}")"
  ln -snf "profiles/${PROFILE}.gitconfig" "$(basename "${TARGET}")"
)
log_success "Active git profile: ${PROFILE}"
