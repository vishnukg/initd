#!/usr/bin/env bash
set -euo pipefail

# Behavior tests for the link/cleanup flow. Run against the host OS — the script
# detects the platform with uname and exercises the corresponding bootstrap path.
# Uses temporary $HOME dirs throughout so the real machine is never touched.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *) echo "Unsupported test platform: $(uname -s)" >&2; exit 1 ;;
esac

TEST_ROOT=""

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/fs.sh"

cleanup() {
  if [[ -n "${TEST_ROOT}" && -d "${TEST_ROOT}" ]]; then
    rm -rf "${TEST_ROOT}"
  fi
}

fail() {
  log_error "$*"
  exit 1
}

new_home() {
  mktemp -d "${TEST_ROOT}/home.XXXXXX"
}

assert_path_exists() {
  path_exists "$1" || fail "Expected path to exist: $1"
}

assert_path_missing() {
  ! path_exists "$1" || fail "Expected path to be absent: $1"
}

assert_symlink() {
  [[ -L "$1" ]] || fail "Expected symlink: $1"
}

assert_file() {
  [[ -f "$1" ]] || fail "Expected file: $1"
}

assert_output_contains() {
  grep -qF "$2" "$1" || fail "Expected $1 to contain: $2"
}

assert_symlink_resolves_to() {
  local path="$1" expected="$2"
  assert_symlink "${path}"
  symlink_points_to "${path}" "${expected}" \
    || fail "Expected ${path} to resolve to ${expected}, got $(readlink "${path}")"
}

run_link() {
  local home="$1" output="$2"
  HOME="${home}" "${ROOT_DIR}/shared/lib/link.sh" "${PLATFORM}" >"${output}" 2>&1
  assert_output_contains "${output}" "Managed symlinks verified."
}

# Returns the list of "home_path:repo_path" entries that would be linked on this platform.
get_managed_links() {
  HOME="${TEST_ROOT}/_inspect_home" bash -c "
    ROOT_DIR='${ROOT_DIR}'
    source '${ROOT_DIR}/shared/managed-links.sh'
    source '${ROOT_DIR}/${PLATFORM}/managed-links.sh'
    printf '%s\n' \"\${MANAGED_LINKS[@]}\"
  "
}

test_clean_link_install() {
  local home output
  home="$(new_home)"
  output="${TEST_ROOT}/clean-link.out"

  run_link "${home}" "${output}"

  local entry home_path repo_path
  while IFS= read -r entry; do
    home_path="${entry%%:*}"
    repo_path="${entry#*:}"
    # Rewrite the test home into the entry (the inspect HOME differs).
    home_path="${home_path/${INSPECT_PREFIX}/${home}}"
    assert_symlink_resolves_to "${home_path}" "${repo_path}"
  done < <(get_managed_links)

  log_success "clean link install (${PLATFORM})"
}

test_platform_links_are_self_contained() {
  local entry repo_path allowed_prefix_1 allowed_prefix_2 forbidden_prefix

  case "${PLATFORM}" in
    macos)
      allowed_prefix_1="${ROOT_DIR}/shared/"
      allowed_prefix_2="${ROOT_DIR}/macos/"
      forbidden_prefix="${ROOT_DIR}/linux/"
      ;;
    linux)
      allowed_prefix_1="${ROOT_DIR}/shared/"
      allowed_prefix_2="${ROOT_DIR}/linux/"
      forbidden_prefix="${ROOT_DIR}/macos/"
      ;;
    *)
      fail "Unsupported platform for self-containment test: ${PLATFORM}"
      ;;
  esac

  while IFS= read -r entry; do
    repo_path="${entry#*:}"

    if [[ "${repo_path}" == "${forbidden_prefix}"* ]]; then
      fail "${PLATFORM} managed link points at the other platform: ${repo_path}"
    fi

    if [[ "${repo_path}" != "${allowed_prefix_1}"* && "${repo_path}" != "${allowed_prefix_2}"* ]]; then
      fail "${PLATFORM} managed link points outside its allowed roots: ${repo_path}"
    fi
  done < <(get_managed_links)

  log_success "platform links are self-contained (${PLATFORM})"
}

test_backup_unmanaged_configs() {
  local home output backup_count
  home="$(new_home)"
  output="${TEST_ROOT}/backup-unmanaged.out"

  mkdir -p \
    "${home}/.config/mise" "${home}/.config/nvim" \
    "${home}/.config/fish" "${home}/.config/ghostty" \
    "${home}/.config/kitty"
  printf 'user mise config\n'    > "${home}/.config/mise/config.toml"
  printf 'user nvim config\n'    > "${home}/.config/nvim/init.lua"
  printf 'user fish config\n'    > "${home}/.config/fish/config.fish"
  printf 'user ghostty config\n' > "${home}/.config/ghostty/config"
  printf 'user kitty config\n'   > "${home}/.config/kitty/kitty.conf"
  printf 'user git config\n'     > "${home}/.gitconfig"

  run_link "${home}" "${output}"

  assert_symlink "${home}/.config/mise"
  assert_symlink "${home}/.config/nvim"
  assert_symlink "${home}/.config/fish"
  assert_symlink "${home}/.config/ghostty"
  assert_symlink "${home}/.config/kitty"
  assert_symlink "${home}/.gitconfig"
  assert_path_exists "${home}/.config/initd-backups"

  backup_count="$(find "${home}/.config/initd-backups" -type f | wc -l | tr -d ' ')"
  [[ "${backup_count}" -ge 6 ]] || fail "Expected at least 6 backed-up files, found ${backup_count}"
  assert_output_contains "${output}" "Backing up unmanaged"

  log_success "unmanaged config backup"
}

test_git_profile() {
  local output
  output="${TEST_ROOT}/git-profile.out"

  # The personal path writes no override file, so it is safe to run against the
  # real repo: it just confirms the baked-in default email is used.
  "${ROOT_DIR}/shared/lib/git-profile.sh" personal >"${output}" 2>&1
  assert_output_contains "${output}" "using the default git email"

  log_success "git profile (personal)"
}

test_broken_managed_link_is_repaired() {
  local home output backup_count
  home="$(new_home)"
  output="${TEST_ROOT}/broken-link.out"

  # A dangling managed symlink must be backed up and replaced with a valid one.
  ln -s "${ROOT_DIR}/shared/configs/git/missing.gitconfig" "${home}/.gitconfig"

  run_link "${home}" "${output}"
  assert_symlink_resolves_to "${home}/.gitconfig" "${ROOT_DIR}/shared/configs/git/gitconfig"
  backup_count="$(find "${home}/.config/initd-backups" -name .gitconfig -type l | wc -l | tr -d ' ')"
  [[ "${backup_count}" -eq 1 ]] || fail "Expected one backed-up broken .gitconfig symlink, found ${backup_count}"

  log_success "broken managed link repair"
}

test_cleanup_managed_links() {
  local home output entry home_path repo_path
  home="$(new_home)"
  output="${TEST_ROOT}/cleanup-managed.out"

  mkdir -p "${home}/.config" "${home}/outside"

  # Pre-create every managed symlink the platform would install.
  while IFS= read -r entry; do
    home_path="${entry%%:*}"
    repo_path="${entry#*:}"
    home_path="${home_path/${INSPECT_PREFIX}/${home}}"
    mkdir -p "$(dirname "${home_path}")"
    ln -s "${repo_path}" "${home_path}"
  done < <(get_managed_links)

  ln -s "${home}/outside/keep" "${home}/.unrelated"
  printf 'real file\n' > "${home}/real-file"

  HOME="${home}" "${ROOT_DIR}/shared/lib/cleanup.sh" "${PLATFORM}" >"${output}" 2>&1

  while IFS= read -r entry; do
    home_path="${entry%%:*}"
    home_path="${home_path/${INSPECT_PREFIX}/${home}}"
    assert_path_missing "${home_path}"
  done < <(get_managed_links)

  assert_symlink "${home}/.unrelated"
  assert_file "${home}/real-file"
  assert_output_contains "${output}" "Cleanup complete."

  log_success "cleanup removes only managed links"
}

main() {
  TEST_ROOT="$(mktemp -d)"
  INSPECT_PREFIX="${TEST_ROOT}/_inspect_home"
  trap cleanup EXIT

  log "Running install behavior tests in ${TEST_ROOT} for platform=${PLATFORM}"
  test_clean_link_install
  test_platform_links_are_self_contained
  test_backup_unmanaged_configs
  test_git_profile
  test_broken_managed_link_is_repaired
  test_cleanup_managed_links
  log_success "All install behavior tests passed."
}

main "$@"
