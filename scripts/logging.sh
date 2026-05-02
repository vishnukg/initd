#!/usr/bin/env bash

# Shared, dependency-free logging helpers for initd setup scripts.
# Colors are enabled only for interactive terminals and can be disabled with NO_COLOR=1.
INITD_RESET=""
INITD_BLUE=""
INITD_GREEN=""
INITD_YELLOW=""
INITD_RED=""
INITD_CYAN=""
INITD_COLORS="0"

if [[ -t 1 && -z "${NO_COLOR:-}" ]] && command -v tput >/dev/null 2>&1; then
  INITD_COLORS="$(tput colors 2>/dev/null || printf '0')"
  if [[ "${INITD_COLORS}" =~ ^[0-9]+$ ]]; then
    if (( INITD_COLORS >= 8 )); then
      INITD_RESET="$(tput sgr0)"
      INITD_BLUE="$(tput setaf 4)"
      INITD_GREEN="$(tput setaf 2)"
      INITD_YELLOW="$(tput setaf 3)"
      INITD_RED="$(tput setaf 1)"
      INITD_CYAN="$(tput setaf 6)"
    fi
  fi
fi

initd_log() {
  local color="$1"
  local marker="$2"
  local message="$3"
  local stream="${4:-stdout}"

  if [[ "${stream}" == "stderr" ]]; then
    printf '%b%s%b %s\n' "${color}" "${marker}" "${INITD_RESET}" "${message}" >&2
    return
  fi

  printf '%b%s%b %s\n' "${color}" "${marker}" "${INITD_RESET}" "${message}"
}

log() {
  initd_log "${INITD_BLUE}" "==>" "$*"
}

log_info() {
  initd_log "${INITD_CYAN}" "::" "$*"
}

log_success() {
  initd_log "${INITD_GREEN}" "OK" "$*"
}

log_warn() {
  initd_log "${INITD_YELLOW}" "!!" "$*" "stderr"
}

log_error() {
  initd_log "${INITD_RED}" "ERR" "$*" "stderr"
}
