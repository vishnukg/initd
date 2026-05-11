#!/usr/bin/env bash

# Shared filesystem helpers. Scripts that call these must source logging.sh first.

# -e returns false for broken symlinks; -L catches them too.
path_exists() {
  local path="$1"
  [[ -e "${path}" || -L "${path}" ]]
}

# initd symlinks use absolute paths, so a string comparison is sufficient.
symlink_points_to() {
  local path="$1"
  local expected="$2"
  [[ -L "${path}" ]] && [[ "$(readlink "${path}")" == "${expected}" ]]
}

verify_symlink_target() {
  local path="$1"
  local expected="$2"

  if [[ ! -L "${path}" ]]; then
    log_error "Managed path was not installed as a symlink: ${path}"
    exit 1
  fi

  if ! symlink_points_to "${path}" "${expected}"; then
    log_error "Managed path points to the wrong target: ${path}"
    log_info "Expected: ${expected}"
    log_info "Resolved: $(readlink "${path}")"
    exit 1
  fi
}

backup_path() {
  local path="$1"
  # Strip $HOME prefix so the backup mirrors the original directory shape.
  # e.g. ~/.config/fish → ${BACKUP_ROOT}/.config/fish
  local relative="${path#"${HOME}/"}" # strips the $HOME/ prefix, e.g. /Users/you/.config/fish → .config/fish
  # The ':' is a no-op command. '${VAR:?msg}' exits with msg if VAR is unset — a bash guard idiom.
  : "${BACKUP_ROOT:?BACKUP_ROOT must be set before calling backup_path}"
  local backup="${BACKUP_ROOT}/${relative}"

  path_exists "${path}" || return 0

  mkdir -p "$(dirname "${backup}")"
  log_warn "Backing up unmanaged ${path} -> ${backup}"
  mv "${path}" "${backup}"
}
