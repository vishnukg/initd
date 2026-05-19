#!/usr/bin/env bash

# Source of truth for cross-platform managed symlinks plus git-profile helpers.
# Platform-specific entries are appended in <platform>/managed-links.sh.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing shared/managed-links.sh}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/fs.sh"

GIT_PROFILES_DIR="${ROOT_DIR}/shared/configs/git/profiles"
DEFAULT_GIT_PROFILE="${GIT_PROFILES_DIR}/personal.gitconfig"

# Format: "home path:repo path".
# Cross-platform configs only. Add platform-only entries in <platform>/managed-links.sh.
MANAGED_LINKS=(
  "${HOME}/.config/fish:${ROOT_DIR}/shared/configs/fish/.config/fish"
  "${HOME}/.config/ghostty:${ROOT_DIR}/shared/configs/ghostty/.config/ghostty"
  "${HOME}/.config/kitty:${ROOT_DIR}/shared/configs/kitty/.config/kitty"
  "${HOME}/.config/mise:${ROOT_DIR}/shared/configs/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/shared/configs/nvim/.config/nvim"
  "${HOME}/.config/tmux:${ROOT_DIR}/shared/configs/tmux/.config/tmux"
)

# Returns true when ${path} is a symlink pointing at one of the curated git profiles.
git_profile_link_is_managed() {
  local path="$1"
  local resolved=""
  [[ -L "${path}" ]] || return 1
  resolved="$(readlink "${path}")"
  # Glob match allows any curated profile name, then -f rejects stale/broken links.
  [[ "${resolved}" == "${GIT_PROFILES_DIR}/"*.gitconfig ]] && [[ -f "${resolved}" ]]
}

verify_git_profile_link() {
  local path="${1:-${HOME}/.gitconfig}"

  if git_profile_link_is_managed "${path}"; then
    return
  fi

  if [[ ! -L "${path}" ]]; then
    log_error "Managed Git profile was not installed as a symlink: ${path}"
  else
    log_error "Managed Git profile points outside initd profiles: ${path}"
    log_info "Resolved: $(readlink "${path}")"
  fi
  exit 1
}
