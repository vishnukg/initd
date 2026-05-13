#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/managed-configs.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run]

Remove initd-managed symlinks from \$HOME.

Options:
  --dry-run      Print what would be removed without changing files.
  -h, --help     Show this help.
EOF
}

remove_link() {
  local path="$1"

  if [[ ! -L "${path}" ]]; then
    if path_exists "${path}"; then
      log "Leaving non-symlink: ${path}"
    else
      log "Already absent: ${path}"
    fi
    return
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "Would remove: ${path} -> $(readlink "${path}")"
    return
  fi

  log "Removing: ${path}"
  rm "${path}"
}

main() {
  local arg managed_link home_path repo_path

  # $# is the number of remaining CLI args. shift consumes one each loop.
  while [[ "$#" -gt 0 ]]; do
    arg="$1"

    if [[ "${arg}" == "--dry-run" ]]; then
      DRY_RUN=1
    elif [[ "${arg}" == "-h" || "${arg}" == "--help" ]]; then
      usage
      return
    else
      log_error "Unknown argument: ${arg}"
      usage >&2
      exit 1
    fi

    shift
  done

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Dry run mode — no files will be removed."
  fi

  log "Removing initd-managed symlinks from ${HOME}"

  # .gitconfig is handled separately — it can point to any file under git/profiles.
  if [[ -L "${HOME}/.gitconfig" ]] && ! git_profile_link_is_managed "${HOME}/.gitconfig"; then
    log_warn "Leaving symlink outside initd ownership: ${HOME}/.gitconfig -> $(readlink "${HOME}/.gitconfig")"
  else
    remove_link "${HOME}/.gitconfig"
  fi

  for managed_link in "${MANAGED_LINKS[@]}"; do
    home_path="${managed_link%%:*}"
    repo_path="${managed_link#*:}"
    if [[ -L "${home_path}" ]] && ! symlink_points_to "${home_path}" "${repo_path}"; then
      log_warn "Leaving symlink outside initd ownership: ${home_path} -> $(readlink "${home_path}")"
    else
      remove_link "${home_path}"
    fi
  done

  log_success "Cleanup complete."
}

main "$@"
