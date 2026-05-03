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

backup_path() {
  local path="$1"
  local relative="${path#"${HOME}/"}"
  local backup=""

  # Backups are intentionally controlled by each caller so one bootstrap run keeps
  # all preserved user files under the same timestamped directory.
  : "${BACKUP_ROOT:?BACKUP_ROOT must be set before calling backup_path}"
  backup="${BACKUP_ROOT}/${relative}"

  if [[ ! -e "${path}" && ! -L "${path}" ]]; then
    return
  fi

  mkdir -p "$(dirname "${backup}")"
  log_warn "Backing up unmanaged ${path} -> ${backup}"
  mv "${path}" "${backup}"
}
