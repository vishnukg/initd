#!/usr/bin/env bash

# Shared path definitions and git-profile helpers.
# Requires: ROOT_DIR must be set; logging.sh must be sourced before this file.
: "${ROOT_DIR:?ROOT_DIR must be set before sourcing scripts/paths.sh}"

# fs.sh is sourced here so callers only need one source line for both.
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/fs.sh"

GIT_PROFILES_DIR="${ROOT_DIR}/git/profiles"
DEFAULT_GIT_PROFILE="${GIT_PROFILES_DIR}/personal.gitconfig"

# Each entry is "runtime path in $HOME : source path in this repo".
# Adding a new managed config means adding one line here and updating the tests.
MANAGED_LINKS=(
  "${HOME}/.config/kitty:${ROOT_DIR}/kitty/.config/kitty"
  "${HOME}/.config/mise:${ROOT_DIR}/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/nvim/.config/nvim"
  "${HOME}/.zshrc:${ROOT_DIR}/zsh/.zshrc"
  "${HOME}/.zprofile:${ROOT_DIR}/zsh/.zprofile"
)

# Returns true when ${path} is a symlink pointing at one of the curated git
# profiles. Used to distinguish an initd-owned gitconfig from a user's own file.
git_profile_link_is_managed() {
  local path="$1"
  local resolved=""

  [[ -L "${path}" ]] || return 1
  resolved="$(readlink "${path}")"
  [[ "${resolved}" == "${GIT_PROFILES_DIR}/"*.gitconfig ]]
}

# Hard assertion version of git_profile_link_is_managed. Exits 1 if the link
# is missing or points somewhere outside the curated profiles directory.
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
