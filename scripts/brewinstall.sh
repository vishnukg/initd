#!/usr/bin/env bash
set -euo pipefail

# This script lives in scripts/, so .. is the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The curated Brewfile is the source of truth that bootstrap uses on every Mac.
BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"

source "${ROOT_DIR}/scripts/logging.sh"

# Script-level state set by parse_args and shared across all functions below.
kind=""
package=""

usage() {
  cat <<'EOF'
Usage: brewinstall [--formula|--cask] <package>

Add a Homebrew formula or cask to platforms/darwin/Brewfile, then install it locally with brew bundle.

Options:
  --formula, --brew  Add as a brew formula
  --cask             Add as a cask
  -h, --help         Show this help
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --formula|--brew) kind="brew" ;;
      --cask)           kind="cask" ;;
      -h|--help)        usage; exit 0 ;;
      -*)               log_error "Unknown option: $1"; usage >&2; exit 1 ;;
      *)
        if [[ -n "${package}" ]]; then
          log_error "Expected one package, got: ${package} and $1"
          usage >&2
          exit 1
        fi
        package="$1"
        ;;
    esac
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
    log_info "Using requested package type: ${kind}"
    return
  fi

  log "Detecting whether ${package} is a formula or cask..."

  local is_formula=0 is_cask=0
  brew info --formula "${package}" >/dev/null 2>&1 && is_formula=1
  brew info --cask    "${package}" >/dev/null 2>&1 && is_cask=1

  if (( is_formula && is_cask )); then
    log_error "${package} exists as both a formula and cask. Re-run with --formula or --cask."
    exit 1
  fi

  if (( is_formula )); then
    kind="brew"
    log_success "Detected formula: ${package}"
    return
  fi

  if (( is_cask )); then
    kind="cask"
    log_success "Detected cask: ${package}"
    return
  fi

  log_error "Could not find ${package} as a Homebrew formula or cask."
  log_info "If this is from a tapped repository, use its full name or tap it first."
  exit 1
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

  log "Adding ${entry} to ${BREWFILE}."
  printf '%s\n' "${entry}" >> "${BREWFILE}"
  log_success "Brewfile updated."
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
