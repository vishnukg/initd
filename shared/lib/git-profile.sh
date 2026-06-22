#!/usr/bin/env bash
set -euo pipefail

# Configure this machine's Git identity. Run as:
#   shared/lib/git-profile.sh [personal|work]
#
# ~/.gitconfig always links to the single base shared/configs/git/gitconfig,
# which carries the default (personal) email. This script only decides whether a
# per-machine override is needed:
#   personal -> nothing to do; the baked-in default email is used.
#   work     -> prompt for a work email and store it in the gitignored
#               shared/configs/git/local.gitconfig, which is included from the
#               base config and overrides the default.
# With no argument it prompts interactively (default: personal).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

LOCAL_GITCONFIG="${ROOT_DIR}/shared/configs/git/local.gitconfig"

usage() {
  cat <<EOF
Usage: ${0##*/} [personal|work]

Configure this machine's Git identity. 'personal' uses the default email baked
into the base config; 'work' stores a separate email in the gitignored
local.gitconfig override.
EOF
}

set_work_email() {
  local existing_email
  existing_email="$(git config --file "${LOCAL_GITCONFIG}" user.email 2>/dev/null || true)"

  if [[ -n "${existing_email}" ]]; then
    log_success "Work git email already set: ${existing_email}"
    return
  fi

  if [[ ! -t 0 ]]; then
    log_warn "No work git email set — run shared/lib/git-profile.sh work interactively to configure it."
    return
  fi

  local email
  printf '%b::%b Work git email for this machine: ' "${INITD_CYAN}" "${INITD_RESET}"
  read -r email

  if [[ -z "${email}" ]]; then
    log_warn "No email entered — re-run shared/lib/git-profile.sh work to set the work email."
    return
  fi

  mkdir -p "$(dirname "${LOCAL_GITCONFIG}")"

  local tmp_config
  if ! tmp_config="$(mktemp "$(dirname "${LOCAL_GITCONFIG}")/local.gitconfig.XXXXXX")"; then
    log_error "Failed to create temp file for git config."
    exit 1
  fi

  printf '[user]\n\temail = %s\n' "${email}" > "${tmp_config}"
  mv "${tmp_config}" "${LOCAL_GITCONFIG}"
  log_success "Work git email set to: ${email}"
}

prompt_profile() {
  local profile
  printf '%b::%b Machine type [personal/work] (default: personal): ' "${INITD_CYAN}" "${INITD_RESET}" >&2
  read -r profile
  printf '%s' "${profile:-personal}"
}

main() {
  local profile="${1:-}"

  if [[ "${profile}" == "-h" || "${profile}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ -z "${profile}" ]]; then
    if [[ -t 0 ]]; then
      profile="$(prompt_profile)"
    else
      profile="personal"
    fi
  fi

  case "${profile}" in
    personal)
      log_success "Personal machine — using the default git email; no override needed."
      ;;
    work)
      set_work_email
      ;;
    *)
      log_error "Unknown git profile: ${profile}"
      log_info "Available profiles: personal, work"
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
