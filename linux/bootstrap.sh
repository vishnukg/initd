#!/usr/bin/env bash
set -euo pipefail

# Linux platform bootstrap. Invoked by the top-level dispatcher when uname=Linux.
# Targets Debian-based systems (Ubuntu, Linux Mint).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX_DIR="${ROOT_DIR}/linux"
SHARED_DIR="${ROOT_DIR}/shared"

PACKAGES_FILE="${LINUX_DIR}/packages.txt"

export BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S).$$}"

# shellcheck disable=SC1091
source "${SHARED_DIR}/lib/logging.sh"

ensure_user_context() {
  if [[ "${EUID}" == "0" ]]; then
    log_error "Do not run bootstrap with sudo. It manages files and the login shell for your normal user."
    exit 1
  fi
}

ensure_debian() {
  if [[ ! -f /etc/debian_version ]]; then
    log_error "linux/bootstrap.sh only supports Debian-based distros (Ubuntu, Linux Mint)."
    exit 1
  fi
  require_command apt-get "to install Debian packages"
}

install_packages() {
  [[ -f "${PACKAGES_FILE}" ]] || { log_error "Missing ${PACKAGES_FILE}"; exit 1; }

  local packages=() missing=() pkg
  # Strip comments and blank lines.
  while IFS= read -r pkg; do
    pkg="${pkg%%#*}"
    pkg="${pkg// /}"
    [[ -z "${pkg}" ]] && continue
    packages+=("${pkg}")
  done < "${PACKAGES_FILE}"

  for pkg in "${packages[@]}"; do
    dpkg -s "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    log_success "All ${#packages[@]} apt packages already installed."
    return
  fi

  log "Installing ${#missing[@]} apt package(s): ${missing[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y "${missing[@]}"
  log_success "apt packages installed."
}

ensure_mise() {
  if command -v mise >/dev/null 2>&1; then
    log_success "mise already installed."
    return
  fi

  require_command curl "to install mise"
  log "Installing mise from mise.run..."
  curl -fsSL --max-time 60 https://mise.run | sh

  # mise installs to ~/.local/bin by default — make it usable for the rest of this run.
  export PATH="${HOME}/.local/bin:${PATH}"
  require_command mise "after mise.run install"
}

ensure_gh() {
  if command -v gh >/dev/null 2>&1; then
    return
  fi
  log "Installing gh CLI from official apt repo..."
  # Per https://github.com/cli/cli/blob/trunk/docs/install_linux.md
  (type -p wget >/dev/null || sudo apt-get install -y wget) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
    && sudo apt-get update -qq \
    && sudo apt-get install -y gh
}

ensure_gh_auth() {
  if gh auth token >/dev/null 2>&1; then
    log_success "gh auth check done."
    return
  fi
  if [[ ! -t 0 ]]; then
    log_warn "gh CLI is not authenticated, and bootstrap is not running interactively."
    log_info "Run gh auth login later, then re-run bootstrap.sh."
    return
  fi
  log "Authenticating gh CLI..."
  gh auth login
}

ensure_fish() {
  require_command fish "after apt install"

  local fish_path
  fish_path="$(command -v fish)"

  if ! grep -qxF "${fish_path}" /etc/shells; then
    log "Adding ${fish_path} to /etc/shells."
    printf '%s\n' "${fish_path}" | sudo tee -a /etc/shells >/dev/null
  else
    log_success "fish already in /etc/shells."
  fi

  local login_shell
  login_shell="$(getent passwd "${USER}" | cut -d: -f7)"
  if [[ "${login_shell}" != "${fish_path}" ]]; then
    log "Setting fish as default shell for ${USER}."
    sudo chsh -s "${fish_path}" "${USER}"
  else
    log_success "fish is already the default shell."
  fi

  log "Syncing fisher plugins..."
  GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)" fish -c "
    if not functions -q fisher
      curl -fsSL --max-time 30 https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
      fisher install jorgebucaran/fisher
    end
    fisher update
  "
}

setup_git_profile() {
  local local_gitconfig="${SHARED_DIR}/configs/git/local.gitconfig"
  local existing_email
  existing_email="$(git config --file "${local_gitconfig}" user.email 2>/dev/null || true)"

  # shellcheck disable=SC1091
  source "${SHARED_DIR}/managed-links.sh"

  if git_profile_link_is_managed "${HOME}/.gitconfig" && [[ -n "${existing_email}" ]]; then
    log_success "Git profile already configured (${existing_email})."
    return
  fi
  if [[ ! -t 0 ]]; then
    log_warn "Git profile needs setup, but bootstrap is not running interactively."
    log_info "Run shared/lib/git-profile.sh personal or work later."
    return
  fi

  log "Setting up Git profile..."
  local git_profile
  printf '%b::%b Machine type [personal/work] (default: personal): ' "${INITD_CYAN}" "${INITD_RESET}"
  read -r git_profile
  git_profile="${git_profile:-personal}"
  "${SHARED_DIR}/lib/git-profile.sh" "${git_profile}"
}

main() {
  ensure_user_context
  ensure_debian

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for Linux."

  install_packages
  ensure_gh
  ensure_mise

  log "Linking managed configs into ${HOME}..."
  "${SHARED_DIR}/lib/link.sh" linux

  log "Running Linux system tweaks..."
  "${LINUX_DIR}/setup.sh"

  log "Checking gh CLI authentication..."
  ensure_gh_auth

  log "Ensuring fish shell is configured..."
  ensure_fish

  log "Trusting shared mise config."
  mise trust "${SHARED_DIR}/configs/mise/.config/mise/config.toml"

  log "Installing shared runtimes and LSP tooling with mise..."
  mise install --yes

  setup_git_profile

  echo
  log_success "initd finished for Linux."
}

main "$@"
