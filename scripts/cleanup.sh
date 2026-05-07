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

# Remove ${path} only if it is a symlink that ${is_owned_fn} confirms initd owns.
# Real files and unrelated symlinks are intentionally left in place.
remove_if_owned() {
  local path="$1"
  local is_owned_fn="$2"

  if [[ ! -L "${path}" ]]; then
    if path_exists "${path}"; then
      log "Leaving non-symlink: ${path}"
    else
      log "Already absent: ${path}"
    fi
    return
  fi

  if ! "${is_owned_fn}" "${path}"; then
    log_warn "Leaving symlink outside initd ownership: ${path} -> $(readlink "${path}")"
    return
  fi

  if (( DRY_RUN )); then
    log "Would remove: ${path} -> $(readlink "${path}")"
    return
  fi

  log "Removing: ${path}"
  rm "${path}"
}

# Ownership predicates used with remove_if_owned.
points_to_expected() {
  symlink_points_to "$1" "${EXPECTED}"
}

main() {
  local link=""

  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; return ;;
      *) log_error "Unknown argument: $1"; usage >&2; exit 1 ;;
    esac
    shift
  done

  log_info "Dry run: ${DRY_RUN}"
  log "Removing initd-managed symlinks from ${HOME}"

  remove_if_owned "${HOME}/.gitconfig" git_profile_link_is_managed
  for link in "${MANAGED_LINKS[@]}"; do
    EXPECTED="${link#*:}" remove_if_owned "${link%%:*}" points_to_expected
  done

  log_success "Cleanup complete."
}

main "$@"
