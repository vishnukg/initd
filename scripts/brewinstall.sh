#!/usr/bin/env bash
set -euo pipefail

# This script lives in scripts/, so .. is the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The curated Brewfile is the source of truth that bootstrap uses on every Mac.
BREWFILE="${ROOT_DIR}/Brewfile"

source "${ROOT_DIR}/scripts/logging.sh"

# Script-level state set by parse_args and shared across all functions below.
kind=""
package=""

usage() {
  cat <<'EOF'
Usage: brewinstall [--formula|--cask] <package>

Add a Homebrew formula or cask to Brewfile, then install it locally with brew bundle.

Options:
  --formula, --brew  Add as a brew formula
  --cask             Add as a cask
  -h, --help         Show this help
EOF
}

parse_args() {
  local arg

  # $# is the number of remaining CLI args. shift consumes one each loop.
  while [[ "$#" -gt 0 ]]; do
    arg="$1"

    if [[ "${arg}" == "--formula" || "${arg}" == "--brew" ]]; then
      kind="brew"
    elif [[ "${arg}" == "--cask" ]]; then
      kind="cask"
    elif [[ "${arg}" == "-h" || "${arg}" == "--help" ]]; then
      usage
      exit 0
    elif [[ "${arg}" == -* ]]; then
      log_error "Unknown option: ${arg}"
      usage >&2
      exit 1
    else
      if [[ -n "${package}" ]]; then
        log_error "Expected one package, got: ${package} and ${arg}"
        usage >&2
        exit 1
      fi
      package="${arg}"
    fi

    shift
  done
}

validate_inputs() {
  if [[ -z "${package}" ]]; then
    log_error "Package name is required."
    usage >&2
    exit 1
  fi

  if [[ ! -f "${BREWFILE}" ]]; then
    log_error "Brewfile not found: ${BREWFILE}"
    exit 1
  fi

  require_command brew "to update and apply ${BREWFILE}"
}

# When --formula/--cask wasn't given, ask Homebrew which one matches.
detect_package_kind() {
  if [[ -n "${kind}" ]]; then
    return
  fi

  log "Detecting whether ${package} is a formula or cask..."

  local is_formula=0 is_cask=0
  if brew info --formula "${package}" >/dev/null 2>&1; then
    is_formula=1
  fi

  if brew info --cask "${package}" >/dev/null 2>&1; then
    is_cask=1
  fi

  if [[ "${is_formula}" == "1" && "${is_cask}" == "1" ]]; then
    log_error "${package} exists as both a formula and cask. Re-run with --formula or --cask."
    exit 1
  elif [[ "${is_formula}" == "1" ]]; then
    kind="brew"
    log_success "Detected formula: ${package}"
  elif [[ "${is_cask}" == "1" ]]; then
    kind="cask"
    log_success "Detected cask: ${package}"
  else
    log_error "Could not find ${package} as a Homebrew formula or cask."
    log_info "If this is from a tapped repository, use its full name or tap it first."
    exit 1
  fi
}

# Append the entry to the Brewfile if it's not already there.
# We deliberately don't reorder existing lines: the Brewfile is a hand-curated
# file in git, and silent reordering hurts diffs. If the file gets messy, edit
# it manually.
update_brewfile() {
  local entry="${kind} \"${package}\""

  if grep -Fxq "${entry}" "${BREWFILE}"; then
    log_info "${entry} is already in ${BREWFILE}; nothing to add."
    return
  fi

  # Write to a temp file then atomically replace, so a failed write cannot
  # corrupt the curated Brewfile.
  local tmp_brewfile
  tmp_brewfile="$(mktemp "${BREWFILE}.XXXXXX")" \
    || { log_error "Failed to create temporary Brewfile."; exit 1; }

  log "Adding ${entry} to ${BREWFILE}."
  if cp "${BREWFILE}" "${tmp_brewfile}" && \
     printf '%s\n' "${entry}" >> "${tmp_brewfile}" && \
     mv "${tmp_brewfile}" "${BREWFILE}"; then
    log_success "Brewfile updated."
    return
  fi

  rm -f "${tmp_brewfile}"
  log_error "Failed to update ${BREWFILE}."
  exit 1
}

apply_brewfile() {
  log "Applying ${BREWFILE} with brew bundle..."
  brew bundle --file "${BREWFILE}"
  log_success "Brewfile applied locally."
}

main() {
  parse_args "$@"
  validate_inputs
  detect_package_kind
  update_brewfile
  apply_brewfile
}

main "$@"
