#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0

source "${ROOT_DIR}/scripts/logging.sh"
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

remove_link() {
  local path="$1"

  if [[ ! -L "${path}" ]]; then
    path_exists "${path}" && log "Leaving non-symlink: ${path}" || log "Already absent: ${path}"
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
  local link="" path="" source=""

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

  for link in "${MANAGED_LINKS[@]}"; do
    path="${link%%:*}"
    source="${link#*:}"
    if [[ -L "${path}" ]] && ! symlink_points_to "${path}" "${source}"; then
      log_warn "Leaving symlink outside initd ownership: ${path} -> $(readlink "${path}")"
    else
      remove_link "${path}"
    fi
  done

  log_success "Cleanup complete."
}

main "$@"
