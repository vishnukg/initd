#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="${HOME}/.gitconfig"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/paths.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [personal|work]

Switch ~/.gitconfig to the requested initd Git profile.
EOF
}

main() {
  local profile="${1:-personal}"
  local source="${GIT_PROFILES_DIR}/${profile}.gitconfig"

  if [[ "${profile}" == "-h" || "${profile}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ ! -f "${source}" ]]; then
    log_error "Unknown git profile: ${profile}"
    log_info "Available profiles: personal, work"
    usage >&2
    exit 1
  fi

  # Refuse to overwrite a file that initd did not create. The user would need
  # to run scripts/link.sh first to migrate it into a managed symlink.
  if path_exists "${TARGET}" && ! git_profile_link_is_managed "${TARGET}"; then
    log_error "${TARGET} already exists and is not an initd-managed Git profile link."
    log_info "Run scripts/link.sh to migrate managed links, or back up the file before switching profiles."
    exit 1
  fi

  log "Linking ${TARGET} -> ${source}."
  # -n: treat an existing symlink-to-directory as a plain file, so the new
  #     link replaces it rather than being created inside it.
  # -f: remove any existing file or symlink at the target before linking.
  ln -snf "${source}" "${TARGET}"
  log_success "Active git profile: ${profile}"
}

main "$@"
