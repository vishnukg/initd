#!/usr/bin/env bash
set -euo pipefail

# This script lives in scripts/, so .. is the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# These package names match top-level stow package directories in the repo.
PACKAGES=(kitty mise nvim zsh)

# Stow reads from ROOT_DIR and creates links under HOME.
STOW_FLAGS=(--restow --dir "${ROOT_DIR}" --target "${HOME}")

# Each item is "HOME-relative target:repo-relative source".
DIRECTORY_LINKS=(
  ".config/kitty:kitty/.config/kitty"
  ".config/mise:mise/.config/mise"
  ".config/nvim:nvim/.config/nvim"
)
LEGACY_ZSHRC_SOURCE='[[ -f "${HOME}/.config/zsh/initd.zsh" ]] && source "${HOME}/.config/zsh/initd.zsh"'
LEGACY_ZPROFILE_SOURCE='[[ -f "${HOME}/.config/zsh/initd.zprofile" ]] && source "${HOME}/.config/zsh/initd.zprofile"'
GITCONFIG="${HOME}/.gitconfig"
XDG_GITCONFIG="${HOME}/.config/git/.gitconfig"
LEGACY_GIT_CONFIG_DIR="${HOME}/.config/git"
LEGACY_GIT_CONFIG_SOURCE="${ROOT_DIR}/git/.config/git"
MANAGED_GITCONFIG="${ROOT_DIR}/git/.gitconfig"
LEGACY_MISE_CONFIG="${ROOT_DIR}/mise.toml"
STOW_OUTPUT=""
VERIFY_WARNING="WARNING: in simulation mode so not modifying filesystem."

# One timestamp per run keeps all preserved user files grouped together.
BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"

cleanup() {
  if [[ -n "${STOW_OUTPUT}" && -f "${STOW_OUTPUT}" ]]; then
    rm -f "${STOW_OUTPUT}"
  fi
}

entry_points_into_source() {
  local entry="$1"
  local source_dir="$2"
  local resolved=""

  if [[ ! -L "${entry}" ]]; then
    return 1
  fi

  resolved="$(resolve_symlink_target "${entry}")"

  [[ "${resolved}" == "${source_dir}" || "${resolved}" == "${source_dir}/"* ]]
}

fold_existing_directory() {
  local target_relative="$1"
  local source_relative="$2"
  local target="${HOME}/${target_relative}"
  local source="${ROOT_DIR}/${source_relative}"
  local entry=""
  local found_entry=0

  if [[ ! -e "${target}" && ! -L "${target}" ]]; then
    return
  fi

  # Direct directory symlinks are the preferred final shape. Anything else at the
  # package root is either already correct or must be preserved before stow runs.
  if [[ -L "${target}" ]]; then
    if [[ "$(resolve_symlink_target "${target}")" == "${source}" ]]; then
      return
    fi

    backup_path "${target}"
    return
  fi

  if [[ ! -d "${target}" ]]; then
    backup_path "${target}"
    return
  fi

  for entry in "${target}"/* "${target}"/.[!.]* "${target}"/..?*; do
    if [[ ! -e "${entry}" && ! -L "${entry}" ]]; then
      continue
    fi

    found_entry=1

    # If any entry is not already an initd-managed symlink, preserve the whole
    # existing directory in backups instead of merging user files with ours.
    if ! entry_points_into_source "${entry}" "${source}"; then
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

remove_legacy_mise_config_link() {
  local path="${HOME}/.config/mise/config.toml"

  if [[ -L "${path}" && "$(resolve_symlink_target "${path}")" == "${LEGACY_MISE_CONFIG}" ]]; then
    log "Removing legacy ${path} symlink."
    rm "${path}"
  fi
}

fold_directory_links() {
  local link=""
  local target_relative=""
  local source_relative=""

  for link in "${DIRECTORY_LINKS[@]}"; do
    target_relative="${link%%:*}"
    source_relative="${link#*:}"
    fold_existing_directory "${target_relative}" "${source_relative}"
  done
}

file_contains_only_line() {
  local path="$1"
  local expected="$2"
  local content=""

  content="$(grep -v '^[[:space:]]*$' "${path}" || true)"
  [[ "${content}" == "${expected}" ]]
}

prepare_zsh_file() {
  local path="$1"
  local legacy_target="$2"
  local legacy_content="$3"
  local managed_target="$4"

  if [[ -L "${path}" && "$(resolve_symlink_target "${path}")" == "${managed_target}" ]]; then
    return
  fi

  # Older initd layouts used tiny loader files and different symlink targets.
  # Remove those known shims, but back up any real user-authored config.
  if [[ -L "${path}" && "$(resolve_symlink_target "${path}")" == "${legacy_target}" ]]; then
    log "Removing legacy ${path} symlink."
    rm "${path}"
    return
  fi

  if [[ -f "${path}" ]] && file_contains_only_line "${path}" "${legacy_content}"; then
    log "Replacing legacy ${path} with a managed symlink."
    rm "${path}"
    return
  fi

  backup_path "${path}"
}

remove_legacy_zsh_config_dir() {
  local path="${HOME}/.config/zsh"
  local legacy_target="${ROOT_DIR}/shell/.config/zsh"

  # The old zsh package lived under ~/.config/zsh. Current initd owns ~/.zshrc
  # and ~/.zprofile directly, so only the known legacy symlink is removed.
  if [[ -L "${path}" && "$(resolve_symlink_target "${path}")" == "${legacy_target}" ]]; then
    log "Removing legacy ${path} symlink."
    rm "${path}"
    return
  fi

  backup_path "${path}"
}

remove_legacy_zsh_links() {
  prepare_zsh_file "${HOME}/.zshrc" "${ROOT_DIR}/zsh-home/.zshrc" "${LEGACY_ZSHRC_SOURCE}" "${ROOT_DIR}/zsh/.zshrc"
  prepare_zsh_file "${HOME}/.zprofile" "${ROOT_DIR}/shell/.config/zsh/initd.zprofile" "${LEGACY_ZPROFILE_SOURCE}" "${ROOT_DIR}/zsh/.zprofile"
  remove_legacy_zsh_config_dir
}

remove_xdg_gitconfig_link() {
  # Older layouts pointed ~/.gitconfig at an XDG git config. Current initd keeps
  # ~/.gitconfig as the compatibility entrypoint, so remove only that known shim.
  if [[ -L "${GITCONFIG}" && "$(resolve_symlink_target "${GITCONFIG}")" == "${XDG_GITCONFIG}" ]]; then
    log "Removing XDG ${GITCONFIG} symlink."
    rm "${GITCONFIG}"
  fi
}

remove_legacy_git_config_dir() {
  # ~/.config/git is no longer a runtime path. Preserve real user content, but
  # remove the old initd symlink so Git has a single source of truth again.
  if [[ -L "${LEGACY_GIT_CONFIG_DIR}" && "$(resolve_symlink_target "${LEGACY_GIT_CONFIG_DIR}")" == "${LEGACY_GIT_CONFIG_SOURCE}" ]]; then
    log "Removing legacy ${LEGACY_GIT_CONFIG_DIR} symlink."
    rm "${LEGACY_GIT_CONFIG_DIR}"
    return
  fi

  backup_path "${LEGACY_GIT_CONFIG_DIR}"
}

ensure_gitconfig_link() {
  # Git is linked manually instead of through stow because ~/.gitconfig is a
  # home-level compatibility file while profile data lives inside git/.
  if [[ -L "${GITCONFIG}" && "$(resolve_symlink_target "${GITCONFIG}")" == "${MANAGED_GITCONFIG}" ]]; then
    return
  fi

  if [[ -e "${GITCONFIG}" || -L "${GITCONFIG}" ]]; then
    backup_path "${GITCONFIG}"
  fi

  log "Linking ${GITCONFIG} -> ${MANAGED_GITCONFIG}."
  ln -s "${MANAGED_GITCONFIG}" "${GITCONFIG}"
}

verify_install() {
  local verify_output=""
  local verify_status=0
  local filtered_output=""

  # A successful stow command is not enough: simulation should report no pending
  # link operations once everything is installed.
  verify_output="$(stow --simulate --verbose=1 --dir "${ROOT_DIR}" --target "${HOME}" "${PACKAGES[@]}" 2>&1)" || verify_status=$?
  filtered_output="$(printf '%s\n' "${verify_output}" | grep -vFx "${VERIFY_WARNING}" || true)"

  if (( verify_status != 0 )) || [[ -n "${filtered_output//[$'\n\r\t ']}" ]]; then
    log_error "stow finished but the managed links are not fully installed yet."

    if [[ -n "${filtered_output//[$'\n\r\t ']}" ]]; then
      printf '%s\n' "${filtered_output}" >&2
    fi

    exit 1
  fi

  log_success "Managed symlinks verified."
}

main() {
  trap cleanup EXIT
  STOW_OUTPUT="$(mktemp)"
  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Stowing packages: ${PACKAGES[*]}"
  log "Target home directory: ${HOME}"
  log "Preparing legacy paths and existing config directories..."
  remove_xdg_gitconfig_link
  remove_legacy_git_config_dir
  remove_legacy_zsh_links
  remove_legacy_mise_config_link
  ensure_gitconfig_link
  fold_directory_links

  log "Running GNU Stow for managed packages..."
  # Capture stow stderr so conflict errors can get a clearer, repo-specific
  # message while still streaming the original output to the terminal.
  if stow "${STOW_FLAGS[@]}" "${PACKAGES[@]}" 2> >(tee "${STOW_OUTPUT}" >&2); then
    verify_install
    return
  fi

  if grep -q "would cause conflicts" "${STOW_OUTPUT}"; then
    echo
    log_error "Stow found existing files in ${HOME} that are not symlinks yet."
    log_info "Remove or move the conflicting files, then re-run one of:"
    log_info "  ~/.config/initd/scripts/stow.sh"
    log_info "  bash ~/.config/initd/bootstrap.sh"
  else
    log_error "stow failed before managed links were fully installed."
  fi

  exit 1
}

main "$@"
