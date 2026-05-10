#!/usr/bin/env bash

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing scripts/paths.sh}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/fs.sh"

GIT_PROFILES_DIR="${ROOT_DIR}/git/profiles"
DEFAULT_GIT_PROFILE="${GIT_PROFILES_DIR}/personal.gitconfig"

# Format: "runtime path in $HOME : source path in this repo".
# To add a managed config, add one entry here and update the tests.
MANAGED_LINKS=(
  "${HOME}/.config/fish:${ROOT_DIR}/fish/.config/fish"
  "${HOME}/.config/kitty:${ROOT_DIR}/kitty/.config/kitty"
  "${HOME}/.config/mise:${ROOT_DIR}/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/nvim/.config/nvim"
  "${HOME}/.config/tmux:${ROOT_DIR}/tmux/.config/tmux"
)

# Returns true when ${path} is a symlink pointing at one of the curated git profiles.
git_profile_link_is_managed() {
  local path="$1"
  local resolved=""
  [[ -L "${path}" ]] || return 1
  resolved="$(readlink "${path}")"
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
    log_info "Resolved: $(readlink "${path}")"
  fi
  exit 1
}
