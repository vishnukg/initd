#!/usr/bin/env bash
set -euo pipefail

# This script lives in scripts/, so .. is the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default to the personal profile when no profile name is provided.
PROFILE="${1:-personal}"

# SOURCE is the requested profile; TARGET is the stable include path used by git/.gitconfig.
SOURCE="${ROOT_DIR}/git/profiles/${PROFILE}.gitconfig"
TARGET="${ROOT_DIR}/git/profile.gitconfig"

source "${ROOT_DIR}/scripts/logging.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [personal|work]

Switch the repo-local Git profile used by ~/.gitconfig.
EOF
}

if [[ "${PROFILE}" == "-h" || "${PROFILE}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "${SOURCE}" ]]; then
  log_error "Unknown git profile: ${PROFILE}"
  log_info "Available profiles: personal, work"
  usage >&2
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
