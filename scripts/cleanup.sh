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

# Remove ${path} when it is a symlink that initd installed.
# is_owned returns 0 when the symlink target is one we recognize as managed.
# Real files and unrelated symlinks are intentionally left in place.
remove_if_owned() {
  local path="$1"
  local is_owned="$2"   # function name; called as: $is_owned "$path"

  if [[ ! -L "${path}" ]]; then
    if path_exists "${path}"; then
      log "Leaving non-symlink: ${path}"
    else
      log "Already absent: ${path}"
    fi
    return
  fi

  if ! "${is_owned}" "${path}"; then
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

# Ownership check for a managed link: the symlink at ${path} must point to the
# expected source under the initd repo.
points_to_managed_source() {
  local path="$1"
  symlink_points_to "${path}" "${EXPECTED_TARGET}"
}

main() {
  local link=""
  local path=""

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

  # The git profile symlink can point at any file under git/profiles, so it has
  # its own ownership predicate.
  remove_if_owned "${HOME}/.gitconfig" git_profile_link_is_managed

  # Each managed link has a fixed expected target. We share remove_if_owned by
  # setting EXPECTED_TARGET (read by points_to_managed_source) for each entry.
  for link in "${MANAGED_LINKS[@]}"; do
    path="${link%%:*}"
    EXPECTED_TARGET="${link#*:}"
    remove_if_owned "${path}" points_to_managed_source
  done

  log_success "Cleanup complete."
}

main "$@"
