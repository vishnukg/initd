#!/usr/bin/env bash
set -euo pipefail

# Switch ~/.gitconfig to one of the curated initd profiles.
# Profiles live under shared/configs/git/profiles/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${HOME}/.gitconfig"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/managed-links.sh"

LOCAL_GITCONFIG="${ROOT_DIR}/shared/configs/git/local.gitconfig"

usage() {
  cat <<EOF
Usage: ${0##*/} [personal|work]

Switch ~/.gitconfig to the requested initd Git profile.
EOF
}

ensure_email() {
  local existing_email
  existing_email="$(git config --file "${LOCAL_GITCONFIG}" user.email 2>/dev/null || true)"

  if [[ -n "${existing_email}" ]]; then
    log_success "Git email: ${existing_email}"
    return
  fi

  if [[ ! -t 0 ]]; then
    log_warn "No git email set — run shared/lib/git-profile.sh interactively to configure it."
    return
  fi

  local email
  printf '%b::%b Git email for this machine: ' "${INITD_CYAN}" "${INITD_RESET}"
  read -r email

  if [[ -z "${email}" ]]; then
    log_warn "No email entered — git commits will lack an email until you re-run this script."
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
  log_success "Git email set to: ${email}"
}

main() {
  local profile="${1:-personal}"

  if [[ "${profile}" == "-h" || "${profile}" == "--help" ]]; then
    usage
    exit 0
  fi

  local profile_file="${GIT_PROFILES_DIR}/${profile}.gitconfig"

  if [[ ! -f "${profile_file}" ]]; then
    log_error "Unknown git profile: ${profile}"
    log_info "Available profiles: personal, work"
    usage >&2
    exit 1
  fi

  if path_exists "${TARGET}" && ! git_profile_link_is_managed "${TARGET}"; then
    log_error "${TARGET} already exists and is not an initd-managed Git profile link."
    log_info "Run shared/lib/link.sh first to migrate managed links."
    exit 1
  fi

  log "Linking ${TARGET} -> ${profile_file}."
  ln -snf "${profile_file}" "${TARGET}"
  log_success "Active git profile: ${profile}"

  ensure_email
}

main "$@"
