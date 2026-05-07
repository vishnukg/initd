#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITCONFIG="${HOME}/.gitconfig"

# Reuse BACKUP_ROOT from the parent bootstrap when present so a single run keeps
# every preserved file under one timestamped folder. Stand-alone invocations of
# this script still get their own folder.
BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)}"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/paths.sh"

# Returns true when ${path} is a symlink pointing into ${source_dir} (or to it).
points_into_source() {
  local path="$1"
  local source_dir="$2"
  local resolved=""

  [[ -L "${path}" ]] || return 1
  resolved="$(resolve_symlink_target "${path}")"
  [[ "${resolved}" == "${source_dir}" || "${resolved}" == "${source_dir}/"* ]]
}

# A "foldable" directory is one that contains only symlinks back into the
# matching initd source. We can safely delete it and replace it with a single
# direct symlink to the source. The subshell isolates `shopt` changes.
directory_is_foldable() {
  local target="$1"
  local source="$2"

  (
    shopt -s nullglob dotglob
    local entry=""
    for entry in "${target}"/*; do
      points_into_source "${entry}" "${source}" || exit 1
    done
  )
}

# Make ${path} ready to receive a fresh `ln -s ${source} ${path}`. Either:
# - it is already absent, or
# - it is a foldable directory that we delete in place, or
# - it is something user-owned that we move to BACKUP_ROOT.
prepare_target() {
  local path="$1"
  local source="$2"

  if ! path_exists "${path}"; then
    return
  fi

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

ensure_git_profile_link() {
  if git_profile_link_is_managed "${GITCONFIG}"; then
    return
  fi

  if path_exists "${GITCONFIG}"; then
    backup_path "${GITCONFIG}"
  fi

  log "Linking ${GITCONFIG} -> ${DEFAULT_GIT_PROFILE}."
  ln -s "${DEFAULT_GIT_PROFILE}" "${GITCONFIG}"
}

main() {
  local link=""

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Target home directory: ${HOME}"

  ensure_git_profile_link
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
