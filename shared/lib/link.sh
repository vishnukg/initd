#!/usr/bin/env bash
set -euo pipefail

# Installs managed symlinks. Run as:
#   shared/lib/link.sh <platform>
# where <platform> is macos or linux.

PLATFORM="${1:?platform required: macos or linux}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITCONFIG="${HOME}/.gitconfig"

BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S).$$}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/managed-links.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/${PLATFORM}/managed-links.sh"

install_managed_link() {
  local home_path="$1"
  local repo_path="$2"

  if ! path_exists "${repo_path}"; then
    log_error "Managed source path does not exist: ${repo_path}"
    log_info "Check shared/managed-links.sh or ${PLATFORM}/managed-links.sh."
    exit 1
  fi

  if symlink_points_to "${home_path}" "${repo_path}"; then
    log "Already linked: ${home_path}"
    return
  fi

  if path_exists "${home_path}"; then
    backup_path "${home_path}"
  fi

  local parent_dir
  parent_dir="$(dirname "${home_path}")"

  if ! mkdir -p "${parent_dir}"; then
    log_error "Failed to create parent directory: ${parent_dir}"
    exit 1
  fi

  log "Linking ${home_path} -> ${repo_path}."
  ln -s "${repo_path}" "${home_path}"
}

main() {
  local managed_link home_path repo_path

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Target home directory: ${HOME}"

  # .gitconfig is handled separately — it can point to any file under git/profiles.
  if ! git_profile_link_is_managed "${GITCONFIG}"; then
    if path_exists "${GITCONFIG}"; then
      backup_path "${GITCONFIG}"
    fi

    log "Linking ${GITCONFIG} -> ${DEFAULT_GIT_PROFILE}."
    ln -s "${DEFAULT_GIT_PROFILE}" "${GITCONFIG}"
  fi

  for managed_link in "${MANAGED_LINKS[@]}"; do
    home_path="${managed_link%%:*}"
    repo_path="${managed_link#*:}"
    install_managed_link "${home_path}" "${repo_path}"
    verify_symlink_target "${home_path}" "${repo_path}"
  done

  verify_git_profile_link "${GITCONFIG}"
  log_success "Managed symlinks verified."
}

main
