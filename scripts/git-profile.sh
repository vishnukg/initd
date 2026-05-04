#!/usr/bin/env bash
set -euo pipefail

# This script lives in scripts/, so .. is the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default to the personal profile when no profile name is provided.
PROFILE="${1:-personal}"

# SOURCE is the requested profile; TARGET is the Git config path that Git reads.
SOURCE="${ROOT_DIR}/git/profiles/${PROFILE}.gitconfig"
TARGET="${HOME}/.gitconfig"
LEGACY_GITCONFIG="${ROOT_DIR}/git/.gitconfig"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [personal|work]

Switch ~/.gitconfig to the requested initd Git profile.
EOF
}

gitconfig_is_switchable() {
  local resolved=""

  if [[ ! -L "${TARGET}" ]]; then
    return 1
  fi

  resolved="$(resolve_symlink_target "${TARGET}")"

  case "${resolved}" in
    "${ROOT_DIR}/git/profiles/personal.gitconfig"|"${ROOT_DIR}/git/profiles/work.gitconfig"|"${LEGACY_GITCONFIG}")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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

if [[ -e "${TARGET}" || -L "${TARGET}" ]] && ! gitconfig_is_switchable; then
  log_error "${TARGET} already exists and is not an initd-managed Git profile link."
  log_info "Run scripts/stow.sh or back up the file before switching profiles."
  exit 1
fi

log "Linking ${TARGET} -> ${SOURCE}."
ln -snf "${SOURCE}" "${TARGET}"
log_success "Active git profile: ${PROFILE}"
