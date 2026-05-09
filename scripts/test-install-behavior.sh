#!/usr/bin/env bash
set -euo pipefail

# This test script lives in scripts/, so .. is the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# TEST_ROOT is created in main and removed by cleanup on exit.
TEST_ROOT=""

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"

cleanup() {
  # Guard: TEST_ROOT is empty ("") until mktemp succeeds in main(). If the
  # script aborts before that point the variable is unset, so we skip the rm.
  if [[ -n "${TEST_ROOT}" && -d "${TEST_ROOT}" ]]; then
    rm -rf "${TEST_ROOT}"
  fi
}

fail() {
  log_error "$*"
  exit 1
}

new_home() {
  # Each test gets its own fake HOME so installer behavior is exercised without
  # touching the real machine.
  mktemp -d "${TEST_ROOT}/home.XXXXXX"
}

assert_path_exists() {
  local path="$1"
  path_exists "${path}" || fail "Expected path to exist: ${path}"
}

assert_path_missing() {
  local path="$1"
  ! path_exists "${path}" || fail "Expected path to be absent: ${path}"
}

assert_symlink() {
  local path="$1"

  [[ -L "${path}" ]] || fail "Expected symlink: ${path}"
}

assert_file() {
  local path="$1"

  [[ -f "${path}" ]] || fail "Expected file: ${path}"
}

assert_output_contains() {
  local path="$1"
  local expected="$2"

  grep -qF "${expected}" "${path}" || fail "Expected ${path} to contain: ${expected}"
}

assert_symlink_resolves_to() {
  local path="$1"
  local expected="$2"

  assert_symlink "${path}"
  symlink_points_to "${path}" "${expected}" \
    || fail "Expected ${path} to resolve to ${expected}, got $(readlink "${path}")"
}

run_link() {
  local home="$1"
  local output="$2"

  HOME="${home}" "${ROOT_DIR}/scripts/link.sh" >"${output}" 2>&1
  assert_output_contains "${output}" "Managed symlinks verified."
}

test_clean_link_install() {
  local home=""
  local output=""

  home="$(new_home)"
  output="${TEST_ROOT}/clean-link.out"

  # Fresh machines should end with every managed runtime path linked into initd.
  run_link "${home}" "${output}"

  assert_symlink_resolves_to "${home}/.config/kitty" "${ROOT_DIR}/kitty/.config/kitty"
  assert_symlink_resolves_to "${home}/.config/mise" "${ROOT_DIR}/mise/.config/mise"
  assert_symlink_resolves_to "${home}/.config/nvim" "${ROOT_DIR}/nvim/.config/nvim"
  assert_symlink_resolves_to "${home}/.gitconfig" "${ROOT_DIR}/git/profiles/personal.gitconfig"
  assert_symlink_resolves_to "${home}/.zshrc" "${ROOT_DIR}/zsh/.zshrc"
  assert_symlink_resolves_to "${home}/.zprofile" "${ROOT_DIR}/zsh/.zprofile"

  log_success "clean link install"
}

test_backup_unmanaged_configs() {
  local home=""
  local output=""
  local backup_count=""

  home="$(new_home)"
  output="${TEST_ROOT}/backup-unmanaged.out"

  mkdir -p "${home}/.config/kitty" "${home}/.config/mise" "${home}/.config/nvim"
  printf 'user kitty config\n' > "${home}/.config/kitty/kitty.conf"
  printf 'user mise config\n' > "${home}/.config/mise/config.toml"
  printf 'user nvim config\n' > "${home}/.config/nvim/init.lua"
  printf 'user git config\n' > "${home}/.gitconfig"
  printf 'user zshrc\n' > "${home}/.zshrc"
  printf 'user zprofile\n' > "${home}/.zprofile"

  # Existing user-authored files must be preserved before initd takes ownership.
  run_link "${home}" "${output}"

  assert_symlink "${home}/.config/kitty"
  assert_symlink "${home}/.config/mise"
  assert_symlink "${home}/.config/nvim"
  assert_symlink "${home}/.gitconfig"
  assert_symlink "${home}/.zshrc"
  assert_symlink "${home}/.zprofile"
  assert_path_exists "${home}/.config/initd-backups"

  backup_count="$(find "${home}/.config/initd-backups" -type f | wc -l | tr -d ' ')"
  [[ "${backup_count}" -ge 6 ]] || fail "Expected at least 6 backed-up files, found ${backup_count}"
  assert_output_contains "${output}" "Backing up unmanaged"

  log_success "unmanaged config backup"
}

test_git_profile_switcher() {
  local home=""
  local output=""

  home="$(new_home)"
  output="${TEST_ROOT}/git-profile.out"

  run_link "${home}" "${output}"

  HOME="${home}" "${ROOT_DIR}/scripts/git-profile.sh" work >>"${output}" 2>&1
  assert_symlink_resolves_to "${home}/.gitconfig" "${ROOT_DIR}/git/profiles/work.gitconfig"
  assert_output_contains "${output}" "Active git profile: work"

  # Re-applying managed links must not reset an explicitly selected profile.
  run_link "${home}" "${output}"
  assert_symlink_resolves_to "${home}/.gitconfig" "${ROOT_DIR}/git/profiles/work.gitconfig"

  HOME="${home}" "${ROOT_DIR}/scripts/git-profile.sh" personal >>"${output}" 2>&1
  assert_symlink_resolves_to "${home}/.gitconfig" "${ROOT_DIR}/git/profiles/personal.gitconfig"
  assert_output_contains "${output}" "Active git profile: personal"

  log_success "git profile switcher"
}

test_cleanup_managed_links() {
  local home=""
  local output=""

  home="$(new_home)"
  output="${TEST_ROOT}/cleanup-managed.out"

  mkdir -p "${home}/.config" "${home}/outside"
  ln -s "${ROOT_DIR}/git/profiles/work.gitconfig" "${home}/.gitconfig"
  ln -s "${ROOT_DIR}/kitty/.config/kitty" "${home}/.config/kitty"
  ln -s "${ROOT_DIR}/mise/.config/mise" "${home}/.config/mise"
  ln -s "${ROOT_DIR}/nvim/.config/nvim" "${home}/.config/nvim"
  ln -s "${ROOT_DIR}/zsh/.zshrc" "${home}/.zshrc"
  ln -s "${ROOT_DIR}/zsh/.zprofile" "${home}/.zprofile"
  ln -s "${home}/outside/keep" "${home}/.unrelated"
  printf 'real file\n' > "${home}/real-file"

  # Cleanup is intentionally conservative: only known initd links disappear.
  HOME="${home}" "${ROOT_DIR}/scripts/cleanup.sh" >"${output}" 2>&1

  assert_path_missing "${home}/.gitconfig"
  assert_path_missing "${home}/.config/kitty"
  assert_path_missing "${home}/.config/mise"
  assert_path_missing "${home}/.config/nvim"
  assert_path_missing "${home}/.zshrc"
  assert_path_missing "${home}/.zprofile"
  assert_symlink "${home}/.unrelated"
  assert_file "${home}/real-file"
  assert_output_contains "${output}" "Cleanup complete."

  log_success "cleanup removes only managed links"
}

test_directory_folding() {
  local home=""
  local output=""

  home="$(new_home)"
  output="${TEST_ROOT}/directory-folding.out"

  mkdir -p "${home}/.config/kitty" "${home}/.config/mise" "${home}/.config/nvim"
  ln -s "${ROOT_DIR}/kitty/.config/kitty/kitty.conf" "${home}/.config/kitty/kitty.conf"
  ln -s "${ROOT_DIR}/mise/.config/mise/config.toml" "${home}/.config/mise/config.toml"
  ln -s "${ROOT_DIR}/nvim/.config/nvim/init.lua" "${home}/.config/nvim/init.lua"

  # Older link output may be many file-level symlinks. The desired shape is one
  # direct directory symlink per package root.
  run_link "${home}" "${output}"

  assert_symlink_resolves_to "${home}/.config/kitty" "${ROOT_DIR}/kitty/.config/kitty"
  assert_symlink_resolves_to "${home}/.config/mise" "${ROOT_DIR}/mise/.config/mise"
  assert_symlink_resolves_to "${home}/.config/nvim" "${ROOT_DIR}/nvim/.config/nvim"
  assert_output_contains "${output}" "Folding"

  log_success "managed directory folding"
}

main() {
  TEST_ROOT="$(mktemp -d)"
  trap cleanup EXIT

  log "Running install behavior tests in ${TEST_ROOT}"
  test_clean_link_install
  test_backup_unmanaged_configs
  test_git_profile_switcher
  test_cleanup_managed_links
  test_directory_folding
  log_success "All install behavior tests passed."
}

main "$@"
