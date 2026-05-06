#!/usr/bin/env bash

# Shared path definitions for initd setup scripts.
# Callers must set ROOT_DIR before sourcing this file.
: "${ROOT_DIR:?ROOT_DIR must be set before sourcing scripts/paths.sh}"

GIT_PROFILES_DIR="${ROOT_DIR}/git/profiles"
DEFAULT_GIT_PROFILE="${GIT_PROFILES_DIR}/personal.gitconfig"
LEGACY_GITCONFIG="${ROOT_DIR}/git/.gitconfig"

GIT_PROFILE_TARGETS=(
  "${GIT_PROFILES_DIR}/personal.gitconfig"
  "${GIT_PROFILES_DIR}/work.gitconfig"
)

# Each item is "runtime path:expected initd source".
MANAGED_LINKS=(
  "${HOME}/.config/kitty:${ROOT_DIR}/kitty/.config/kitty"
  "${HOME}/.config/mise:${ROOT_DIR}/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/nvim/.config/nvim"
  "${HOME}/.zshrc:${ROOT_DIR}/zsh/.zshrc"
  "${HOME}/.zprofile:${ROOT_DIR}/zsh/.zprofile"
)

# Known symlinks from older initd layouts. These can be removed safely when found.
LEGACY_LINKS=(
  "${HOME}/.gitconfig:${LEGACY_GITCONFIG}"
  "${HOME}/.config/git:${ROOT_DIR}/git/.config/git"
  "${HOME}/.config/zsh:${ROOT_DIR}/shell/.config/zsh"
  "${HOME}/.zshrc:${ROOT_DIR}/zsh-home/.zshrc"
  "${HOME}/.config/mise/config.toml:${ROOT_DIR}/mise.toml"
)

LEGACY_XDG_GITCONFIG="${HOME}/.config/git/.gitconfig"
LEGACY_GIT_CONFIG_DIR="${HOME}/.config/git"
LEGACY_GIT_CONFIG_SOURCE="${ROOT_DIR}/git/.config/git"
LEGACY_ZSH_CONFIG_DIR="${HOME}/.config/zsh"
LEGACY_ZSH_CONFIG_SOURCE="${ROOT_DIR}/shell/.config/zsh"
LEGACY_ZSHRC_SOURCE='[[ -f "${HOME}/.config/zsh/initd.zsh" ]] && source "${HOME}/.config/zsh/initd.zsh"'
LEGACY_ZPROFILE_SOURCE='[[ -f "${HOME}/.config/zsh/initd.zprofile" ]] && source "${HOME}/.config/zsh/initd.zprofile"'

git_profile_source_is_managed() {
  local source="$1"
  local expected=""

  for expected in "${GIT_PROFILE_TARGETS[@]}"; do
    if [[ "${source}" == "${expected}" ]]; then
      return 0
    fi
  done

  return 1
}

git_profile_link_is_managed() {
  local path="$1"

  [[ -L "${path}" ]] && git_profile_source_is_managed "$(resolve_symlink_target "${path}")"
}

verify_git_profile_link() {
  local path="${1:-${HOME}/.gitconfig}"
  local label="${2:-}"
  local resolved=""

  if git_profile_link_is_managed "${path}"; then
    if [[ -n "${label}" ]]; then
      log_success "Verified ${label}."
    fi
    return
  fi

  if [[ ! -L "${path}" ]]; then
    log_error "Managed Git profile was not installed as a symlink: ${path}"
    exit 1
  fi

  resolved="$(resolve_symlink_target "${path}")"
  log_error "Managed Git profile points outside initd profiles: ${path}"
  log_info "Resolved: ${resolved}"
  exit 1
}
