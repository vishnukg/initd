#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITCONFIG="${HOME}/.gitconfig"

BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"
source "${ROOT_DIR}/scripts/paths.sh"

is_initd_link_inside_package() {
  local entry="$1"
  local source_dir="$2"

  if [[ ! -L "${entry}" ]]; then
    return 1
  fi

  local resolved="$(resolve_symlink_target "${entry}")"
  [[ "${resolved}" == "${source_dir}" || "${resolved}" == "${source_dir}/"* ]]
}

replace_old_file_links_with_directory_link() {
  local target="$1"
  local source="$2"
  local entry=""
  local found_entry=0

  if [[ ! -d "${target}" || -L "${target}" ]]; then
    return
  fi

  for entry in "${target}"/* "${target}"/.[!.]* "${target}"/..?*; do
    if ! path_exists "${entry}"; then
      continue
    fi

    found_entry=1

    if ! is_initd_link_inside_package "${entry}" "${source}"; then
      backup_path "${target}"
      return
    fi
  done

  if (( found_entry )); then
    log "Folding ${target} into a direct symlink."
    for entry in "${target}"/* "${target}"/.[!.]* "${target}"/..?*; do
      if path_exists "${entry}"; then
        rm "${entry}"
      fi
    done
  else
    log "Replacing empty ${target} with a direct symlink."
  fi

  rmdir "${target}"
}

install_managed_link() {
  local path="$1"
  local source="$2"

  if symlink_points_to "${path}" "${source}"; then
    log "Already linked: ${path}"
    return
  fi

  if [[ -d "${path}" && -d "${source}" && ! -L "${path}" ]]; then
    replace_old_file_links_with_directory_link "${path}" "${source}"
  fi

  if path_exists "${path}"; then
    backup_path "${path}"
  fi

  mkdir -p "$(dirname "${path}")"
  log "Linking ${path} -> ${source}."
  ln -s "${source}" "${path}"
}

file_has_only_expected_line() {
  local path="$1"
  local expected="$2"
  local content=""

  if [[ ! -f "${path}" ]]; then
    return 1
  fi

  content="$(grep -v '^[[:space:]]*$' "${path}" || true)"
  [[ "${content}" == "${expected}" ]]
}

remove_legacy_link_if_present() {
  local path="$1"
  local expected="$2"

  if symlink_points_to "${path}" "${expected}"; then
    log "Removing legacy ${path} symlink."
    rm "${path}"
  fi
}

remove_legacy_loader_file_if_present() {
  local path="$1"
  local expected="$2"

  if file_has_only_expected_line "${path}" "${expected}"; then
    log "Replacing legacy ${path} with a managed symlink."
    rm "${path}"
  fi
}

ensure_git_profile_link() {
  if git_profile_link_is_managed "${GITCONFIG}"; then
    return
  fi

  if symlink_points_to "${GITCONFIG}" "${LEGACY_GITCONFIG}"; then
    log "Replacing legacy ${GITCONFIG} Git config link."
    rm "${GITCONFIG}"
  fi

  if path_exists "${GITCONFIG}"; then
    backup_path "${GITCONFIG}"
  fi

  log "Linking ${GITCONFIG} -> ${DEFAULT_GIT_PROFILE}."
  ln -s "${DEFAULT_GIT_PROFILE}" "${GITCONFIG}"
}

remove_old_initd_layout() {
  local link=""

  remove_legacy_link_if_present "${GITCONFIG}" "${LEGACY_XDG_GITCONFIG}"
  for link in "${LEGACY_LINKS[@]}"; do
    remove_legacy_link_if_present "${link%%:*}" "${link#*:}"
  done

  backup_path "${LEGACY_GIT_CONFIG_DIR}"

  remove_legacy_link_if_present "${HOME}/.zprofile" "${ROOT_DIR}/shell/.config/zsh/initd.zprofile"
  remove_legacy_loader_file_if_present "${HOME}/.zshrc" "${LEGACY_ZSHRC_SOURCE}"
  remove_legacy_loader_file_if_present "${HOME}/.zprofile" "${LEGACY_ZPROFILE_SOURCE}"
  backup_path "${LEGACY_ZSH_CONFIG_DIR}"
}

install_managed_links() {
  local link=""

  for link in "${MANAGED_LINKS[@]}"; do
    install_managed_link "${link%%:*}" "${link#*:}"
  done
}

verify_all_links() {
  local link=""

  verify_git_profile_link "${GITCONFIG}"
  for link in "${MANAGED_LINKS[@]}"; do
    verify_symlink_target "${link%%:*}" "${link#*:}"
  done
  log_success "Managed symlinks verified."
}

main() {
  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Target home directory: ${HOME}"
  log "Preparing legacy paths and existing config directories..."
  remove_old_initd_layout
  ensure_git_profile_link

  log "Linking managed config paths..."
  install_managed_links

  verify_all_links
}

main "$@"
