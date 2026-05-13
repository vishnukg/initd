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

  if (( DRY_RUN )); then
    log "Would remove: ${path} -> $(readlink "${path}")"
    return
  fi

  log "Removing: ${path}"
  rm "${path}"
}

main() {
  local managed_link home_path repo_path

  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; return ;;
      *) log_error "Unknown argument: $1"; usage >&2; exit 1 ;;
    esac
    shift
  done

  (( DRY_RUN )) && log_info "Dry run mode — no files will be removed."
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
