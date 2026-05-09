#!/usr/bin/env bash

# Shared logging helpers. Colors via ANSI escapes; honors NO_COLOR (https://no-color.org).
# log_warn/log_error write to stderr so they surface even when stdout is redirected.

INITD_RESET="" INITD_BLUE="" INITD_GREEN="" INITD_YELLOW="" INITD_RED="" INITD_CYAN=""

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  INITD_RESET=$'\033[0m'   INITD_BLUE=$'\033[34m'  INITD_GREEN=$'\033[32m'
  INITD_YELLOW=$'\033[33m' INITD_RED=$'\033[31m'   INITD_CYAN=$'\033[36m'
fi

log()         { printf '%b==>%b %s\n' "${INITD_BLUE}"   "${INITD_RESET}" "$*"; }
log_info()    { printf '%b::%b %s\n'  "${INITD_CYAN}"   "${INITD_RESET}" "$*"; }
log_success() { printf '%bOK%b %s\n'  "${INITD_GREEN}"  "${INITD_RESET}" "$*"; }
log_warn()    { printf '%b!!%b %s\n'  "${INITD_YELLOW}" "${INITD_RESET}" "$*" >&2; }
log_error()   { printf '%bERR%b %s\n' "${INITD_RED}"    "${INITD_RESET}" "$*" >&2; }

require_command() {
  local command_name="$1"
  local context="$2"
  command -v "${command_name}" >/dev/null || {
    log_error "${command_name} is required ${context}."
    exit 1
  }
}
