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
  local target="$1" src="$2"
  (
    shopt -s nullglob dotglob
    local entry="" resolved=""
    for entry in "${target}"/*; do
      [[ -L "${entry}" ]] || exit 1
      resolved="$(readlink "${entry}")"
      [[ "${resolved}" == "${src}" || "${resolved}" == "${src}/"* ]] || exit 1
    done
  )
}

prepare_target() {
  local path="$1"
  local src="$2"

  path_exists "${path}" || return 0

  if [[ -d "${path}" && ! -L "${path}" && -d "${src}" ]] \
     && directory_is_foldable "${path}" "${src}"; then
    log "Folding ${path} into a direct symlink."
    rm -rf "${path}"
    return
  fi

  backup_path "${path}"
}

install_managed_link() {
  local path="$1"
  local src="$2"

  if symlink_points_to "${path}" "${src}"; then
    log "Already linked: ${path}"
    return
  fi

  prepare_target "${path}" "${src}"
  mkdir -p "$(dirname "${path}")"
  log "Linking ${path} -> ${src}."
  ln -s "${src}" "${path}"
}

main() {
  local link="" path="" src=""

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
  done

  verify_git_profile_link "${GITCONFIG}"
  for link in "${MANAGED_LINKS[@]}"; do
    path="${link%%:*}" # everything before the colon — destination in $HOME
    src="${link#*:}"   # everything after the colon  — source in this repo
    verify_symlink_target "${path}" "${src}"
  done
  log_success "Managed symlinks verified."
}

main "$@"
