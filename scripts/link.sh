#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITCONFIG="${HOME}/.gitconfig"

BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)}"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/paths.sh"

# A foldable directory contains only symlinks into the matching initd source —
# replace it with a single direct symlink. Subshell isolates shopt changes.
directory_is_foldable() {
  local target="$1" source="$2"
  (
    shopt -s nullglob dotglob
    local entry="" resolved=""
    for entry in "${target}"/*; do
      [[ -L "${entry}" ]] || exit 1
      resolved="$(readlink "${entry}")"
      [[ "${resolved}" == "${source}" || "${resolved}" == "${source}/"* ]] || exit 1
    done
  )
}

prepare_target() {
  local path="$1"
  local source="$2"

  path_exists "${path}" || return 0

  if [[ -d "${path}" && ! -L "${path}" && -d "${source}" ]] \
     && directory_is_foldable "${path}" "${source}"; then
    log "Folding ${path} into a direct symlink."
    rm -rf "${path}"
    return
  fi

  backup_path "${path}"
}

install_managed_link() {
  local path="$1"
  local source="$2"

  if symlink_points_to "${path}" "${source}"; then
    log "Already linked: ${path}"
    return
  fi

  prepare_target "${path}" "${source}"
  mkdir -p "$(dirname "${path}")"
  log "Linking ${path} -> ${source}."
  ln -s "${source}" "${path}"
}

main() {
  local link=""

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Target home directory: ${HOME}"

  # .gitconfig is handled separately — it can point to any file under git/profiles.
  if ! git_profile_link_is_managed "${GITCONFIG}"; then
    path_exists "${GITCONFIG}" && backup_path "${GITCONFIG}"
    log "Linking ${GITCONFIG} -> ${DEFAULT_GIT_PROFILE}."
    ln -s "${DEFAULT_GIT_PROFILE}" "${GITCONFIG}"
  fi

  for link in "${MANAGED_LINKS[@]}"; do
    install_managed_link "${link%%:*}" "${link#*:}"
  done

  verify_git_profile_link "${GITCONFIG}"
  for link in "${MANAGED_LINKS[@]}"; do
    verify_symlink_target "${link%%:*}" "${link#*:}"
  done
  log_success "Managed symlinks verified."
}

main "$@"
