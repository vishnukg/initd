#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
LEGACY_ONLY=0

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"
source "${ROOT_DIR}/scripts/paths.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--legacy-only]

Remove initd-managed symlinks from \$HOME.

Options:
  --dry-run      Print what would be removed without changing files.
  --legacy-only  Remove only legacy initd symlinks from older layouts.
  -h, --help     Show this help.
EOF
}

remove_link() {
  local path="$1"
  local expected="$2"
  local label="$3"
  local resolved=""

  if [[ ! -L "${path}" ]]; then
    if [[ -e "${path}" ]]; then
      log "Leaving non-symlink ${path}"
    else
      log "Already absent: ${path}"
    fi
    return
  fi

  resolved="$(resolve_symlink_target "${path}")"

  if [[ "${resolved}" != "${expected}" ]]; then
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

remove_git_profile_link() {
  local path="${HOME}/.gitconfig"
  local resolved=""

  if [[ ! -L "${path}" ]]; then
    if [[ -e "${path}" ]]; then
      log "Leaving non-symlink ${path}"
    else
      log "Already absent: ${path}"
    fi
    return
  fi

  resolved="$(resolve_symlink_target "${path}")"

  for expected in "${GIT_PROFILE_TARGETS[@]}"; do
    if [[ "${resolved}" == "${expected}" ]]; then
      if (( DRY_RUN )); then
        log "Would remove managed Git profile symlink: ${path} -> $(readlink "${path}")"
        return
      fi

      log "Removing managed Git profile symlink: ${path}"
      rm "${path}"
      return
    fi
  done

  log_warn "Leaving symlink outside initd ownership: ${path} -> $(readlink "${path}")"
}

remove_legacy_link() {
  local path="$1"
  local expected="$2"
  local resolved=""

  if [[ ! -L "${path}" ]]; then
    return
  fi

  resolved="$(resolve_symlink_target "${path}")"

  if [[ "${resolved}" != "${expected}" ]]; then
    return
  fi

  if (( DRY_RUN )); then
    log "Would remove legacy symlink: ${path} -> $(readlink "${path}")"
    return
  fi

  log "Removing legacy symlink: ${path}"
  rm "${path}"
}

remove_empty_dir() {
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
      --legacy-only)
        LEGACY_ONLY=1
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

  log_info "Dry run: ${DRY_RUN}; legacy-only: ${LEGACY_ONLY}"
  log "Removing initd-managed symlinks from ${HOME}"

  # Normal cleanup removes current managed links first. Legacy cleanup always
  # runs too, because old initd shims can safely coexist with current links.
  if (( ! LEGACY_ONLY )); then
    log "Checking current managed symlinks..."
    remove_git_profile_link
    for link in "${MANAGED_LINKS[@]}"; do
      remove_link "${link%%:*}" "${link#*:}" "managed symlink"
    done
  fi

  log "Checking legacy initd symlinks..."
  for link in "${LEGACY_LINKS[@]}"; do
    remove_legacy_link "${link%%:*}" "${link#*:}"
  done

  if (( ! DRY_RUN && ! LEGACY_ONLY )); then
    remove_empty_dir "${HOME}/.config/mise"
  fi

  log_success "Cleanup complete."
}

main "$@"
