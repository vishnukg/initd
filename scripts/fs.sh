#!/usr/bin/env bash

# Shared filesystem helpers. Scripts that call verify_symlink_target or
# backup_path must source scripts/logging.sh first (both call log_* functions).

# Returns true for files, directories, and symlinks — including broken symlinks.
# The -L check is necessary because -e returns false for a symlink whose target
# does not exist, which would cause us to skip backing it up or skip cleaning it.
path_exists() {
  local path="$1"
  [[ -e "${path}" || -L "${path}" ]]
}

# Returns true when ${path} is a symlink pointing exactly at ${expected}.
# All initd symlinks are created with absolute paths, so readlink returns the
# full target path and a simple string comparison is sufficient.
symlink_points_to() {
  local path="$1"
  local expected="$2"
  [[ -L "${path}" ]] && [[ "$(readlink "${path}")" == "${expected}" ]]
}

# Hard assertion: exits 1 with a clear error if the symlink is missing or wrong.
# Called after install to confirm every managed link landed correctly.
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

# Moves ${path} to a timestamped backup directory so initd can take ownership
# without destroying the user's existing file.
backup_path() {
  local path="$1"

  # Strip the HOME prefix so the backup mirrors the original directory shape.
  # e.g. ~/.zshrc becomes ${BACKUP_ROOT}/.zshrc instead of a deeply nested path.
  local relative="${path#"${HOME}/"}"

  # BACKUP_ROOT is exported by bootstrap so all scripts in a single run share
  # one timestamped folder, making it easy to find and restore everything.
  : "${BACKUP_ROOT:?BACKUP_ROOT must be set before calling backup_path}"
  local backup="${BACKUP_ROOT}/${relative}"

  path_exists "${path}" || return 0

  mkdir -p "$(dirname "${backup}")"
  log_warn "Backing up unmanaged ${path} -> ${backup}"
  mv "${path}" "${backup}"
}
