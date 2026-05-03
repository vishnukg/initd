#!/usr/bin/env bash
set -euo pipefail

# This script lives in scripts/, so .. is the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The curated Brewfile is the source of truth that bootstrap uses on every Mac.
BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"

source "${ROOT_DIR}/scripts/logging.sh"

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
      --formula|--brew)
        kind="brew"
        ;;
      --cask)
        kind="cask"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        log_error "Unknown option: $1"
        usage >&2
        exit 1
        ;;
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

  if [[ "${package}" == *\"* ]]; then
    log_error "Package names with double quotes are not supported: ${package}"
    exit 1
  fi

  if [[ ! -f "${BREWFILE}" ]]; then
    log_error "Brewfile not found: ${BREWFILE}"
    exit 1
  fi

  if ! command -v brew >/dev/null 2>&1; then
    log_error "brew is required to update and apply ${BREWFILE}."
    exit 1
  fi
}

detect_package_kind() {
  if [[ -n "${kind}" ]]; then
    log_info "Using requested package type: ${kind}"
    return
  fi

  log "Detecting whether ${package} is a formula or cask..."

  local formula_found=0
  local cask_found=0

  if brew info --formula "${package}" >/dev/null 2>&1; then
    formula_found=1
  fi

  if brew info --cask "${package}" >/dev/null 2>&1; then
    cask_found=1
  fi

  if (( formula_found && ! cask_found )); then
    kind="brew"
    log_success "Detected formula: ${package}"
    return
  fi

  if (( cask_found && ! formula_found )); then
    kind="cask"
    log_success "Detected cask: ${package}"
    return
  fi

  if (( formula_found && cask_found )); then
    log_error "${package} exists as both a formula and cask. Re-run with --formula or --cask."
    exit 1
  fi

  log_error "Could not find ${package} as a Homebrew formula or cask."
  log_info "If this is from a tapped repository, use its full name or tap it first."
  exit 1
}

append_group() {
  local group_file="$1"
  local output_file="$2"
  local mode="${3:-sort}"

  if [[ ! -s "${group_file}" ]]; then
    return
  fi

  if [[ -s "${output_file}" ]]; then
    printf '\n' >> "${output_file}"
  fi

  if [[ "${mode}" == "preserve-order" ]]; then
    awk '!seen[$0]++' "${group_file}" >> "${output_file}"
  else
    LC_ALL=C sort -u "${group_file}" >> "${output_file}"
  fi
}

tidy_brewfile() {
  local entry="$1"
  local tmpdir
  local tidy_file

  tmpdir="$(mktemp -d)"
  tidy_file="${tmpdir}/Brewfile"

  # grep returns 1 when no lines match. The `|| true` keeps that normal case from
  # stopping the script while `set -e` is enabled.
  grep -E '^tap "' "${BREWFILE}" > "${tmpdir}/taps" || true
  grep -E '^brew "' "${BREWFILE}" > "${tmpdir}/brews" || true
  grep -E '^cask "' "${BREWFILE}" > "${tmpdir}/casks" || true
  grep -E '^mas "' "${BREWFILE}" > "${tmpdir}/mas" || true
  grep -Ev '^(tap|brew|cask|mas) "|^$' "${BREWFILE}" > "${tmpdir}/other" || true

  case "${kind}" in
    brew)
      printf '%s\n' "${entry}" >> "${tmpdir}/brews"
      ;;
    cask)
      printf '%s\n' "${entry}" >> "${tmpdir}/casks"
      ;;
    *)
      log_error "Unsupported package type: ${kind}"
      rm -rf "${tmpdir}"
      exit 1
      ;;
  esac

  : > "${tidy_file}"
  append_group "${tmpdir}/other" "${tidy_file}" "preserve-order"
  append_group "${tmpdir}/taps" "${tidy_file}"
  append_group "${tmpdir}/brews" "${tidy_file}"
  append_group "${tmpdir}/casks" "${tidy_file}"
  append_group "${tmpdir}/mas" "${tidy_file}"
  printf '\n' >> "${tidy_file}"

  mv "${tidy_file}" "${BREWFILE}"
  rm -rf "${tmpdir}"
}

update_brewfile() {
  local entry="${kind} \"${package}\""

  if grep -Fxq "${entry}" "${BREWFILE}"; then
    log_info "${entry} is already in ${BREWFILE}."
    log "Tidying ${BREWFILE} to keep sections sorted and deduplicated."
  else
    log "Adding ${entry} to ${BREWFILE}."
  fi

  tidy_brewfile "${entry}"
  log_success "Brewfile updated and tidied."
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
