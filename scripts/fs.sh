#!/usr/bin/env bash

# Shared filesystem helpers for initd setup scripts.

resolve_symlink_target() {
  local path="$1"
  local target=""
  local target_dir=""
  local target_base=""

  # Tests compare real destinations, so normalize relative symlinks into stable
  # absolute paths instead of relying on whatever spelling readlink returns.
  target="$(readlink "${path}")"

  if [[ "${target}" = /* ]]; then
    printf '%s\n' "${target}"
    return
  fi

  target_dir="$(dirname "${path}")/$(dirname "${target}")"
  target_base="$(basename "${target}")"

  if [[ -d "${target_dir}" ]]; then
    (
      cd "${target_dir}"
      printf '%s/%s\n' "$(pwd -P)" "${target_base}"
    )
    return
  fi

  printf '%s/%s\n' "${target_dir}" "${target_base}"
}

path_exists() {
  local path="$1"

  [[ -e "${path}" || -L "${path}" ]]
}

symlink_points_to() {
  local path="$1"
  local expected="$2"

  [[ -L "${path}" ]] && [[ "$(resolve_symlink_target "${path}")" == "${expected}" ]]
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
    log_info "Resolved: $(resolve_symlink_target "${path}")"
    exit 1
  fi
}

backup_path() {
  local path="$1"

  # Convert an absolute HOME path into a HOME-relative path, so backups keep the
  # same directory shape under BACKUP_ROOT.
  local relative="${path#"${HOME}/"}"
  local backup=""

  # Backups are intentionally controlled by each caller so one bootstrap run keeps
  # all preserved user files under the same timestamped directory.
  : "${BACKUP_ROOT:?BACKUP_ROOT must be set before calling backup_path}"
  backup="${BACKUP_ROOT}/${relative}"

  if ! path_exists "${path}"; then
    return
  fi

  mkdir -p "$(dirname "${backup}")"
  log_warn "Backing up unmanaged ${path} -> ${backup}"
  mv "${path}" "${backup}"
}
