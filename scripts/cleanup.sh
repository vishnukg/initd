#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"
source "${ROOT_DIR}/scripts/paths.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run]

Remove initd-managed symlinks from \$HOME.

Options:
  --dry-run      Print what would be removed without changing files.
  -h, --help     Show this help.
EOF
}

remove_managed_link_if_owned() {
  local path="$1"
  local expected="$2"
  local label="$3"

  if [[ ! -L "${path}" ]]; then
    if path_exists "${path}"; then
      log "Leaving non-symlink ${path}"
    else
      log "Already absent: ${path}"
    fi
    return
  fi

  if ! symlink_points_to "${path}" "${expected}"; then
    log_warn "Leaving symlink outside initd ownership: ${path} -> $(readlink "${path}")"
    return
  fi

  if (( DRY_RUN )); then
    log "Would remove ${label}: ${path} -> $(readlink "${path}")"
    return
  fi

  # Only symlinks that resolve to known initd targets are removed; real files and
  # unrelated symlinks are intentionally left in place.
  log "Removing ${label}: ${path}"
  rm "${path}"
}

remove_managed_git_profile_link() {
  local path="${HOME}/.gitconfig"

  if [[ ! -L "${path}" ]]; then
    if path_exists "${path}"; then
      log "Leaving non-symlink ${path}"
    else
      log "Already absent: ${path}"
    fi
    return
  fi

  if ! git_profile_link_is_managed "${path}"; then
    log_warn "Leaving symlink outside initd ownership: ${path} -> $(readlink "${path}")"
    return
  fi

  if (( DRY_RUN )); then
    log "Would remove managed Git profile symlink: ${path} -> $(readlink "${path}")"
    return
  fi

  log "Removing managed Git profile symlink: ${path}"
  rm "${path}"
}

remove_legacy_link_if_owned() {
  local path="$1"
  local expected="$2"

  if ! symlink_points_to "${path}" "${expected}"; then
    return
  fi

  if (( DRY_RUN )); then
    log "Would remove legacy symlink: ${path} -> $(readlink "${path}")"
    return
  fi

  log "Removing legacy symlink: ${path}"
  rm "${path}"
}

remove_empty_directory_if_safe() {
  local path="$1"

  if [[ ! -d "${path}" || -L "${path}" ]]; then
    return
  fi

  # Cleanup should not remove directories that still contain user files. rmdir
  # gives us that safety for free because it only succeeds on empty directories.
  if rmdir "${path}" 2>/dev/null; then
    log "Removed empty directory: ${path}"
  fi
}

main() {
  local link=""

  while (($#)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        usage
        return
        ;;
      *)
        log_error "Unknown argument: $1"
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  log_info "Dry run: ${DRY_RUN}"
  log "Removing initd-managed symlinks from ${HOME}"

  log "Checking current managed symlinks..."
  remove_managed_git_profile_link
  for link in "${MANAGED_LINKS[@]}"; do
    remove_managed_link_if_owned "${link%%:*}" "${link#*:}" "managed symlink"
  done

  log "Checking legacy initd symlinks..."
  for link in "${LEGACY_LINKS[@]}"; do
    remove_legacy_link_if_owned "${link%%:*}" "${link#*:}"
  done

  if (( ! DRY_RUN )); then
    remove_empty_directory_if_safe "${HOME}/.config/mise"
  fi

  log_success "Cleanup complete."
}

main "$@"
