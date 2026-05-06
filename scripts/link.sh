#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITCONFIG="${HOME}/.gitconfig"

BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"
source "${ROOT_DIR}/scripts/paths.sh"

entry_points_to_source() {
  local entry="$1"
  local source_dir="$2"
  local resolved=""

  if [[ ! -L "${entry}" ]]; then
    return 1
  fi

  resolved="$(resolve_symlink_target "${entry}")"

  [[ "${resolved}" == "${source_dir}" || "${resolved}" == "${source_dir}/"* ]]
}

prepare_directory_target() {
  local target="$1"
  local source="$2"
  local entry=""
  local found_entry=0

  if [[ ! -d "${target}" || -L "${target}" ]]; then
    return
  fi

  for entry in "${target}"/* "${target}"/.[!.]* "${target}"/..?*; do
    if [[ ! -e "${entry}" && ! -L "${entry}" ]]; then
      continue
    fi

    found_entry=1

    if ! entry_points_to_source "${entry}" "${source}"; then
      backup_path "${target}"
      return
    fi
  done

  if (( found_entry )); then
    log "Folding ${target} into a direct symlink."
    for entry in "${target}"/* "${target}"/.[!.]* "${target}"/..?*; do
      if [[ -e "${entry}" || -L "${entry}" ]]; then
        rm "${entry}"
      fi
    done
  else
    log "Replacing empty ${target} with a direct symlink."
  fi

  rmdir "${target}"
}

link_managed_path() {
  local path="$1"
  local source="$2"
  local resolved=""

  if [[ -L "${path}" ]]; then
    resolved="$(resolve_symlink_target "${path}")"
    if [[ "${resolved}" == "${source}" ]]; then
      log "Already linked: ${path}"
      return
    fi

    backup_path "${path}"
  elif [[ -d "${path}" && -d "${source}" ]]; then
    prepare_directory_target "${path}" "${source}"
  elif [[ -e "${path}" ]]; then
    backup_path "${path}"
  fi

  if [[ -e "${path}" || -L "${path}" ]]; then
    backup_path "${path}"
  fi

  mkdir -p "$(dirname "${path}")"
  log "Linking ${path} -> ${source}."
  ln -s "${source}" "${path}"
}

file_contains_only_line() {
  local path="$1"
  local expected="$2"
  local content=""

  if [[ ! -f "${path}" ]]; then
    return 1
  fi

  content="$(grep -v '^[[:space:]]*$' "${path}" || true)"
  [[ "${content}" == "${expected}" ]]
}

remove_known_legacy_link() {
  local path="$1"
  local expected="$2"

  if [[ -L "${path}" && "$(resolve_symlink_target "${path}")" == "${expected}" ]]; then
    log "Removing legacy ${path} symlink."
    rm "${path}"
  fi
}

remove_legacy_loader_file() {
  local path="$1"
  local expected="$2"

  if file_contains_only_line "${path}" "${expected}"; then
    log "Replacing legacy ${path} with a managed symlink."
    rm "${path}"
  fi
}

remove_legacy_xdg_gitconfig_link() {
  if [[ -L "${GITCONFIG}" && "$(resolve_symlink_target "${GITCONFIG}")" == "${LEGACY_XDG_GITCONFIG}" ]]; then
    log "Removing XDG ${GITCONFIG} symlink."
    rm "${GITCONFIG}"
  fi
}

ensure_gitconfig_link() {
  local resolved=""
  local expected=""

  if [[ -L "${GITCONFIG}" ]]; then
    resolved="$(resolve_symlink_target "${GITCONFIG}")"

    for expected in "${GIT_PROFILE_TARGETS[@]}"; do
      if [[ "${resolved}" == "${expected}" ]]; then
        return
      fi
    done

    if [[ "${resolved}" == "${LEGACY_GITCONFIG}" ]]; then
      log "Replacing legacy ${GITCONFIG} Git config link."
      rm "${GITCONFIG}"
    fi
  fi

  if [[ -e "${GITCONFIG}" || -L "${GITCONFIG}" ]]; then
    backup_path "${GITCONFIG}"
  fi

  log "Linking ${GITCONFIG} -> ${DEFAULT_GIT_PROFILE}."
  ln -s "${DEFAULT_GIT_PROFILE}" "${GITCONFIG}"
}

prepare_legacy_paths() {
  remove_legacy_xdg_gitconfig_link
  remove_known_legacy_link "${LEGACY_GIT_CONFIG_DIR}" "${LEGACY_GIT_CONFIG_SOURCE}"
  backup_path "${LEGACY_GIT_CONFIG_DIR}"

  remove_known_legacy_link "${HOME}/.zshrc" "${ROOT_DIR}/zsh-home/.zshrc"
  remove_known_legacy_link "${HOME}/.zprofile" "${ROOT_DIR}/shell/.config/zsh/initd.zprofile"
  remove_legacy_loader_file "${HOME}/.zshrc" "${LEGACY_ZSHRC_SOURCE}"
  remove_legacy_loader_file "${HOME}/.zprofile" "${LEGACY_ZPROFILE_SOURCE}"
  remove_known_legacy_link "${LEGACY_ZSH_CONFIG_DIR}" "${LEGACY_ZSH_CONFIG_SOURCE}"
  backup_path "${LEGACY_ZSH_CONFIG_DIR}"

  remove_known_legacy_link "${HOME}/.config/mise/config.toml" "${ROOT_DIR}/mise.toml"
}

verify_symlink_target() {
  local path="$1"
  local expected="$2"

  if [[ ! -L "${path}" ]]; then
    log_error "Managed path was not installed as a symlink: ${path}"
    exit 1
  fi

  if [[ "$(resolve_symlink_target "${path}")" != "${expected}" ]]; then
    log_error "Managed path points to the wrong target: ${path}"
    log_info "Expected: ${expected}"
    log_info "Resolved: $(resolve_symlink_target "${path}")"
    exit 1
  fi
}

verify_git_profile_link() {
  local resolved=""
  local expected=""

  if [[ ! -L "${GITCONFIG}" ]]; then
    log_error "Managed Git profile was not installed as a symlink: ${GITCONFIG}"
    exit 1
  fi

  resolved="$(resolve_symlink_target "${GITCONFIG}")"
  for expected in "${GIT_PROFILE_TARGETS[@]}"; do
    if [[ "${resolved}" == "${expected}" ]]; then
      return
    fi
  done

  log_error "Managed Git profile points outside initd profiles: ${GITCONFIG}"
  log_info "Resolved: ${resolved}"
  exit 1
}

verify_install() {
  local link=""

  verify_git_profile_link
  for link in "${MANAGED_LINKS[@]}"; do
    verify_symlink_target "${link%%:*}" "${link#*:}"
  done
  log_success "Managed symlinks verified."
}

main() {
  local link=""

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Target home directory: ${HOME}"
  log "Preparing legacy paths and existing config directories..."
  prepare_legacy_paths
  ensure_gitconfig_link

  log "Linking managed config paths..."
  for link in "${MANAGED_LINKS[@]}"; do
    link_managed_path "${link%%:*}" "${link#*:}"
  done

  verify_install
}

main "$@"
