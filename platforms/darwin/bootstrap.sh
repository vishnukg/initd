#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BREWFILE="${ROOT_DIR}/platforms/darwin/Brewfile"
DOCKER_CASK="docker-desktop"
DOCKER_APP="/Applications/Docker.app"

# Exported so scripts/link.sh reuses the same timestamped folder.
export BACKUP_ROOT="${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S)"

source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/paths.sh"

# Script-scoped so the EXIT trap in main() can still reference it after main() returns.
brewfile_tmp=""

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log_success "Xcode Command Line Tools already installed."
    return
  fi

  log_warn "Xcode Command Line Tools are required. Launching installer..."
  # --install exits non-zero if an install is already in progress; || true prevents set -e from aborting.
  xcode-select --install || true
  log_info "Finish the Xcode Command Line Tools install, then re-run ./bootstrap.sh"
  exit 1
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log_success "Homebrew already installed."
  else
    log "Homebrew not found. Installing..."
    # NONINTERACTIVE suppresses the "Press RETURN to continue" prompt.
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Apple Silicon installs to /opt/homebrew; Intel to /usr/local.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  require_command brew "but was not found after Homebrew setup"
}

cleanup_legacy_mason_state() {
  # initd previously managed LSP servers + linters/formatters via mason.nvim.
  # Those tools are now installed by mise (see mise/config.toml).
  #
  # On machines that ran an older initd, this leaves two kinds of stale state:
  #
  #   1. ~/.local/share/nvim/mason/ — Mason's install dir. Orphaned once the
  #      mason.nvim plugin is gone. Always safe to remove (lazy.nvim will not
  #      recreate it).
  #
  #   2. Homebrew packages that have moved into mise. We only uninstall
  #      packages that are (a) currently installed via brew, AND (b) not
  #      listed in the curated Brewfile. That conjunction is the safety net:
  #      a user who re-added one of these to the Brewfile keeps it.
  #
  # Both checks are no-ops on a fresh machine, so this function is safe to
  # run unconditionally on every bootstrap.
  local mason_dir="${HOME}/.local/share/nvim/mason"
  if [[ -d "${mason_dir}" ]]; then
    log "Removing legacy Mason install dir ${mason_dir}..."
    rm -rf "${mason_dir}"
    log_success "Mason install dir removed."
  fi

  # The asdf-uv plugin was briefly installed by an early version of this
  # config when uv was mistakenly listed as a mise-managed tool. The plugin
  # has a broken metadata.lua that causes mise to fail when resolving the
  # built-in uv: backend. Remove it so mise falls back to the built-in.
  local mise_uv_plugin="${HOME}/.local/share/mise/plugins/uv"
  if [[ -d "${mise_uv_plugin}" ]]; then
    log "Removing stale mise asdf-uv plugin (interferes with uv: backend)..."
    rm -rf "${mise_uv_plugin}"
    log_success "Stale uv plugin removed."
  fi

  local stale_brews=(black golangci-lint yamlfmt)
  local pkg
  for pkg in "${stale_brews[@]}"; do
    if brew list --formula "${pkg}" >/dev/null 2>&1 \
        && ! grep -qE "^brew \"${pkg}\"" "${BREWFILE}"; then
      log "Uninstalling stale Homebrew formula ${pkg} (now managed by mise)..."
      if brew uninstall --formula "${pkg}" >/dev/null 2>&1; then
        log_success "${pkg} removed."
      else
        log_warn "Could not uninstall ${pkg} (likely a dependency of another formula); leaving in place. The mise-managed version will still take precedence on PATH."
      fi
    fi
  done
}

ensure_fish() {
  require_command fish "after brew bundle"
  local fish_path
  fish_path="$(command -v fish)"

  # Register fish as an allowed shell so chsh accepts it
  if ! grep -qxF "${fish_path}" /etc/shells; then
    log "Adding ${fish_path} to /etc/shells."
    printf '%s\n' "${fish_path}" | sudo tee -a /etc/shells > /dev/null
  else
    log_success "fish already in /etc/shells."
  fi

  # dscl avoids the interactive password prompt that chsh requires
  if [[ "${SHELL}" != "${fish_path}" ]]; then
    log "Setting fish as default shell for ${USER}."
    sudo dscl . -create "/Users/${USER}" UserShell "${fish_path}"
  else
    log_success "fish is already the default shell."
  fi

  # Install fisher if missing, then sync all plugins listed in fish_plugins
  log "Syncing fisher plugins..."
  fish -c "
    if not functions -q fisher
      curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
      fisher install jorgebucaran/fisher
    end
    fisher update
  "

}

setup_git_profile() {
  log "Setting up Git profile..."
  local git_profile
  printf '%b::%b Machine type [personal/work] (default: personal): ' "${INITD_CYAN}" "${INITD_RESET}"
  read -r git_profile
  git_profile="${git_profile:-personal}"
  "${ROOT_DIR}/scripts/git-profile.sh" "${git_profile}"
}

main() {
  brewfile_tmp="$(mktemp)"
  # Also cleans up the .tmp file the Docker filter below may create.
  trap 'rm -f "${brewfile_tmp}" "${brewfile_tmp}.tmp"' EXIT

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for macOS."

  ensure_xcode_clt
  ensure_homebrew

  # If Docker.app exists outside Homebrew, strip the cask so brew bundle doesn't
  # fail trying to install into an already-occupied path.
  cp "${BREWFILE}" "${brewfile_tmp}"
  if [[ -d "${DOCKER_APP}" ]] && ! brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1; then
    log_warn "Skipping Docker cask: /Applications/Docker.app already exists outside Homebrew."
    grep -Ev "^[[:space:]]*cask[[:space:]]+[\"']${DOCKER_CASK}[\"'][[:space:]]*$" \
      "${brewfile_tmp}" > "${brewfile_tmp}.tmp"
    mv "${brewfile_tmp}.tmp" "${brewfile_tmp}"
  fi

  log "Installing Homebrew packages and casks..."
  brew bundle --file "${brewfile_tmp}"

  # brew bundle skips casks whose receipt exists even when the app was manually deleted.
  if brew list --cask "${DOCKER_CASK}" >/dev/null 2>&1 && [[ ! -d "${DOCKER_APP}" ]]; then
    log_warn "Docker Desktop receipt exists but app is missing. Reinstalling..."
    brew reinstall --cask "${DOCKER_CASK}"
  fi

  require_command mise "after brew bundle"

  log "Linking managed configs into ${HOME}..."
  "${ROOT_DIR}/scripts/link.sh"

  log "Ensuring fish shell is configured..."
  ensure_fish

  log "Trusting shared mise config."
  mise trust "${ROOT_DIR}/mise/.config/mise/config.toml"

  log "Installing shared runtimes and LSP tooling with mise..."
  mise install --yes

  cleanup_legacy_mason_state

  log "Applying macOS defaults..."
  "${ROOT_DIR}/platforms/darwin/macos.sh"

  setup_git_profile

  echo
  log_success "initd finished for macOS."
}

main "$@"
