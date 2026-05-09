#!/usr/bin/env bash
set -euo pipefail

# This script lives in platforms/darwin, so ../.. is the repository root.
# Using an absolute ROOT_DIR lets bootstrap be run from any directory.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"
DOCKER_CASK="docker-desktop"
DOCKER_APP="/Applications/Docker.app"
OH_MY_ZSH_DIR="${HOME}/.oh-my-zsh"
OH_MY_ZSH_REPO="https://github.com/ohmyzsh/ohmyzsh.git"

# Exported so scripts/link.sh reuses the same timestamped folder, keeping all
# backups from one bootstrap run grouped together.
export BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/paths.sh"

# Declared at script scope, not inside main(), so the EXIT trap can still
# reference it after main() returns — bash local variables go out of scope
# when their function exits, which would trigger an "unbound variable" error
# under set -u when the trap fires.
work_brewfile=""

# Exits with a clear message if ${command_name} is not on PATH.
require_command() {
  local command_name="$1"
  local context="$2"
  command -v "${command_name}" >/dev/null || {
    log_error "${command_name} is required ${context}."
    exit 1
  }
}

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log_success "Xcode Command Line Tools already installed."
    return
  fi

  log_warn "Xcode Command Line Tools are required. Launching installer..."
  # --install launches a background GUI installer and exits immediately with a
  # non-zero code if an install is already in progress. || true prevents set -e
  # from treating that as fatal — the user still needs to finish the GUI and
  # re-run bootstrap.
  xcode-select --install || true
  log_info "Finish the Xcode Command Line Tools install, then re-run ./bootstrap.sh"
  exit 1
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log_success "Homebrew already installed."
  else
    log "Homebrew not found. Installing Homebrew..."
    # NONINTERACTIVE suppresses the "Press RETURN to continue" prompt that
    # would stall an unattended run.
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Apple Silicon installs to /opt/homebrew; Intel installs to /usr/local.
  # `brew shellenv` outputs export statements for PATH, MANPATH, etc. — we
  # eval them so brew is on PATH for the remainder of this script without
  # requiring the user to open a new shell first.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  require_command brew "but was not found after Homebrew setup"
}

# Returns true when OH_MY_ZSH_DIR is a git checkout of the upstream Oh My Zsh
# repo. Checks both HTTPS and SSH remote URLs since either may have been used.
oh_my_zsh_is_installed() {
  local remote=""
  [[ -d "${OH_MY_ZSH_DIR}/.git" ]] || return 1
  remote="$(git -C "${OH_MY_ZSH_DIR}" remote get-url origin 2>/dev/null || true)"
  [[ "${remote}" == "${OH_MY_ZSH_REPO}" || "${remote}" == "git@github.com:ohmyzsh/ohmyzsh.git" ]]
}

ensure_oh_my_zsh() {
  # Fast path: if it's a clean checkout, just pull the latest changes.
  if oh_my_zsh_is_installed && [[ -z "$(git -C "${OH_MY_ZSH_DIR}" status --porcelain)" ]]; then
    log "Updating Oh My Zsh in ${OH_MY_ZSH_DIR}."
    # --ff-only ensures we never create a merge commit in the managed checkout.
    # If upstream has diverged the merge will fail, and we fall through to a
    # clean reinstall below.
    if git -C "${OH_MY_ZSH_DIR}" fetch --quiet origin \
       && git -C "${OH_MY_ZSH_DIR}" merge --ff-only --quiet '@{u}'; then
      return
    fi
    log_warn "Could not fast-forward Oh My Zsh; reinstalling."
  fi

  # Anything else (missing, dirty, wrong repo, or ff failure): back up whatever
  # is there and clone a fresh copy.
  path_exists "${OH_MY_ZSH_DIR}" && backup_path "${OH_MY_ZSH_DIR}"
  log "Installing Oh My Zsh into ${OH_MY_ZSH_DIR}."
  # --depth=1 is a shallow clone — we only need the latest snapshot, not the
  # full commit history, which keeps the download fast.
  git clone --quiet --depth=1 "${OH_MY_ZSH_REPO}" "${OH_MY_ZSH_DIR}"
}

main() {
  work_brewfile="$(mktemp)"
  # The EXIT trap runs unconditionally when the script ends — whether it
  # succeeds, hits a set -e failure, or is interrupted. It deletes both the
  # main working copy and the intermediate .tmp file that the Docker grep
  # filter below may create, so neither leaks on the filesystem.
  trap 'rm -f "${work_brewfile}" "${work_brewfile}.tmp"' EXIT

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for macOS."

  ensure_xcode_clt
  ensure_homebrew

  # Copy the Brewfile to a temp file. If Docker.app already exists outside
  # Homebrew we strip docker-desktop from the copy — brew bundle would fail
  # trying to install a cask whose .app is already present at the target path.
  cp "${BREWFILE}" "${work_brewfile}"
  if [[ -d "${DOCKER_APP}" ]] && ! brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1; then
    log_warn "Skipping Docker cask: /Applications/Docker.app already exists outside Homebrew."
    # grep can't write back to the file it's reading, so we filter into a
    # separate .tmp file and then atomically replace the original with mv.
    grep -Ev "^[[:space:]]*cask[[:space:]]+[\"']${DOCKER_CASK}[\"'][[:space:]]*$" \
      "${work_brewfile}" > "${work_brewfile}.tmp"
    mv "${work_brewfile}.tmp" "${work_brewfile}"
  fi
  log "Installing Homebrew packages and casks..."
  brew bundle --file "${work_brewfile}"

  # brew bundle skips a cask it considers already installed, even if the app
  # was manually deleted and only the Homebrew receipt remains. Catch that case
  # and force a reinstall so Docker.app actually lands in /Applications.
  if brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1 && [[ ! -d "${DOCKER_APP}" ]]; then
    log_warn "Docker Desktop receipt exists but app is missing. Reinstalling..."
    brew reinstall --cask "${DOCKER_CASK}"
  fi
  require_command mise "after brew bundle"

  log "Ensuring Oh My Zsh is installed..."
  ensure_oh_my_zsh

  log "Linking managed configs into ${HOME}..."
  "${ROOT_DIR}/scripts/link.sh"

  log "Trusting shared mise config."
  mise trust "${ROOT_DIR}/mise/.config/mise/config.toml"

  log "Installing shared runtimes with mise..."
  mise install --yes

  log "Applying macOS defaults..."
  "${ROOT_DIR}/platforms/darwin/macos.sh"

  echo
  log_success "initd finished for macOS."
}

main "$@"
