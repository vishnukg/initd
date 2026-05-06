#!/usr/bin/env bash
set -euo pipefail

# This script lives in scripts/, so .. is the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default to the personal profile when no profile name is provided.
PROFILE="${1:-personal}"

# SOURCE is the requested profile; TARGET is the Git config path that Git reads.
TARGET="${HOME}/.gitconfig"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"
source "${ROOT_DIR}/scripts/paths.sh"

SOURCE="${GIT_PROFILES_DIR}/${PROFILE}.gitconfig"

usage() {
  cat <<EOF
Usage: ${0##*/} [personal|work]

Switch ~/.gitconfig to the requested initd Git profile.
EOF
}

gitconfig_is_switchable() {
  if [[ ! -L "${TARGET}" ]]; then
    return 1
  fi

  git_profile_link_is_managed "${TARGET}" || symlink_points_to "${TARGET}" "${LEGACY_GITCONFIG}"
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

if path_exists "${TARGET}" && ! gitconfig_is_switchable; then
  log_error "${TARGET} already exists and is not an initd-managed Git profile link."
  log_info "Run scripts/link.sh to migrate managed links, or back up the file before switching profiles."
  exit 1
fi

log "Linking ${TARGET} -> ${SOURCE}."
ln -snf "${SOURCE}" "${TARGET}"
log_success "Active git profile: ${PROFILE}"
