#!/usr/bin/env bash

# Shared path definitions for initd setup scripts.
# Callers must source scripts/logging.sh before this file (helpers below call
# log_error / log_info), and must set ROOT_DIR.
: "${ROOT_DIR:?ROOT_DIR must be set before sourcing scripts/paths.sh}"

# paths.sh helpers depend on fs.sh helpers, so we source it here. That way the
# order of `source` lines in callers does not matter.
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/fs.sh"

GIT_PROFILES_DIR="${ROOT_DIR}/git/profiles"
DEFAULT_GIT_PROFILE="${GIT_PROFILES_DIR}/personal.gitconfig"

# Each item is "runtime path:expected initd source".
MANAGED_LINKS=(
  "${HOME}/.config/kitty:${ROOT_DIR}/kitty/.config/kitty"
  "${HOME}/.config/mise:${ROOT_DIR}/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/nvim/.config/nvim"
  "${HOME}/.zshrc:${ROOT_DIR}/zsh/.zshrc"
  "${HOME}/.zprofile:${ROOT_DIR}/zsh/.zprofile"
)

# Returns true when ${path} is a symlink pointing at one of git/profiles/*.gitconfig.
git_profile_link_is_managed() {
  local path="$1"
  local resolved=""

  [[ -L "${path}" ]] || return 1
  resolved="$(resolve_symlink_target "${path}")"
  [[ "${resolved}" == "${GIT_PROFILES_DIR}/"*.gitconfig ]]
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
    log_info "Resolved: $(resolve_symlink_target "${path}")"
  fi
  exit 1
}
