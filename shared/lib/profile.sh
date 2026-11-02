#!/usr/bin/env bash

# Which machine is this? Sourced (needs ROOT_DIR): by shared/managed-links.sh,
# which links the dev box configs on a personal profile only, and by each
# platform bootstrap, which prints the summary at the start and the end.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing shared/lib/profile.sh}"

# Must match personalEmail in shared/lib/git-profile.mjs.
INITD_PERSONAL_EMAIL="vishnukg@gmail.com"

# The email git-profile.mjs wrote into local.gitconfig, or nothing.
# Global/system git config are ignored: git parses them even with --file,
# and an unreadable ~/.gitconfig would otherwise read as "no email".
initd_email() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    git config --file "${ROOT_DIR}/shared/configs/git/local.gitconfig" user.email 2>/dev/null || true
}

# personal | work | unset
initd_profile() {
  local email
  email="$(initd_email)"
  if [[ -z "${email}" ]]; then
    echo unset
  elif [[ "${email}" == "${INITD_PERSONAL_EMAIL}" ]]; then
    echo personal
  else
    echo work
  fi
}

# "macOS 27.2 (arm64)", "Fedora Linux 44 (Workstation Edition) (x86_64)", ...
initd_os() {
  local name
  if [[ "$(uname -s)" == Darwin ]]; then
    name="macOS $(sw_vers -productVersion 2>/dev/null || echo unknown)"
  else
    # shellcheck disable=SC1091
    name="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-Linux}}")" || name="Linux"
  fi
  echo "${name} ($(uname -m))"
}

# Needs logging.sh. $1 is the platform bootstrap.sh was given (macos|linux|vm).
log_bootstrap_summary() {
  local profile email
  profile="$(initd_profile)"
  email="$(initd_email)"
  log "initd ${1} bootstrap"
  log_info "OS:       $(initd_os)"
  case "${profile}" in
    unset) log_info "Profile:  not set yet (bootstrap asks for personal or work)" ;;
    *)     log_info "Profile:  ${profile} (${email})" ;;
  esac
  # shared/configs/git/gitconfig includes local.gitconfig by this literal path,
  # so a clone elsewhere links fine but git then refuses to commit.
  if [[ "${ROOT_DIR}" != "${HOME}/.config/initd" ]]; then
    log_warn "initd is at ${ROOT_DIR}, not ~/.config/initd: git will not find local.gitconfig (no email, so no commits)."
  fi
}
