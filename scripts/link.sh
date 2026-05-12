#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITCONFIG="${HOME}/.gitconfig"

BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S).$$}"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/paths.sh"

install_managed_link() {
  local path="$1"
  local src="$2"

  if symlink_points_to "${path}" "${src}"; then
    log "Already linked: ${path}"
    return
  fi

  path_exists "${path}" && backup_path "${path}"
  mkdir -p "$(dirname "${path}")" \
    || { log_error "Failed to create parent directory: $(dirname "${path}")"; exit 1; }
  log "Linking ${path} -> ${src}."
  ln -s "${src}" "${path}"
}

main() {
  local link path src

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Target home directory: ${HOME}"

  # .gitconfig is handled separately — it can point to any file under git/profiles.
  if ! git_profile_link_is_managed "${GITCONFIG}"; then
    path_exists "${GITCONFIG}" && backup_path "${GITCONFIG}"
    log "Linking ${GITCONFIG} -> ${DEFAULT_GIT_PROFILE}."
    ln -s "${DEFAULT_GIT_PROFILE}" "${GITCONFIG}"
  fi

  for link in "${MANAGED_LINKS[@]}"; do
    path="${link%%:*}" # everything before the colon — destination in $HOME
    src="${link#*:}"   # everything after the colon  — source in this repo
    install_managed_link "${path}" "${src}"
    verify_symlink_target "${path}" "${src}"
  done

  verify_git_profile_link "${GITCONFIG}"
  log_success "Managed symlinks verified."
}

main "$@"
