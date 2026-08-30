#!/usr/bin/env bash
set -euo pipefail

# Linux platform bootstrap. Invoked by the top-level dispatcher when uname=Linux.
# Targets Fedora Workstation 44+ (dnf5). Several packages (Hyprland ecosystem,
# hyprmoncfg, and Ghostty) aren't in Fedora's official repos and are pulled
# from COPR; see the ensure_* / install_packages functions below for which.

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

ensure_fedora() {
  if [[ ! -f /etc/fedora-release ]]; then
    log_error "linux/bootstrap.sh only supports Fedora."
    exit 1
  fi
  require_command dnf "to install Fedora packages"
}

ensure_docker() {
  local account_name="${USER:-$(id -un)}"
  local docker_repo=/etc/yum.repos.d/docker-ce.repo

  # Docker's packages include its own compatible containerd. Do not silently
  # remove a user's existing runtime, containers, or Docker-compatible tools.
  local conflicts=() package
  for package in moby-engine podman-docker containerd runc; do
    rpm -q "${package}" >/dev/null 2>&1 && conflicts+=("${package}")
  done
  if [[ "${#conflicts[@]}" -gt 0 ]]; then
    log_error "Docker's official packages conflict with: ${conflicts[*]}"
    log_info "Remove those packages first, then re-run bootstrap.sh. Existing container data is left untouched."
    return 1
  fi

  if ! rpm -q docker-ce >/dev/null 2>&1; then
    log "Installing Docker Engine from Docker's official dnf repo..."
    if [[ ! -f "${docker_repo}" ]]; then
      sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    fi
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    log_success "Docker Engine installed."
  else
    log_success "Docker Engine already installed."
  fi

  # docker.socket, not docker.service: the daemon is socket-activated so it
  # starts on the first docker command instead of idling at ~130 MB (dockerd
  # plus containerd) through every session. `enable --now docker` would resolve
  # to docker.service and pin it running, undoing that. containerd is
  # WantedBy=docker.service, so it follows on activation with no entry here.
  #
  # Quickshell's bar polls `docker ps` every 15s and would defeat this by
  # waking the daemon each tick, so shell.qml guards that poll behind
  # `systemctl is-active docker.service` — see linux/configs/quickshell/shell.qml.
  sudo systemctl disable --now docker.service >/dev/null 2>&1 || true
  sudo systemctl enable --now docker.socket
  if id -nG "${account_name}" | grep -qw docker; then
    log_success "${account_name} already belongs to the docker group."
  else
    sudo usermod -aG docker "${account_name}"
    log_warn "Added ${account_name} to the docker group. Log out and back in before using Docker without sudo."
  fi
}

ensure_coprs() {
  local enabled
  enabled="$(dnf copr list 2>/dev/null)"
  local copr
  for copr in "$@"; do
    if grep -qF "${copr}" <<< "${enabled}"; then
      continue
    fi
    log "Enabling COPR ${copr}..."
    sudo dnf copr enable -y "${copr}"
  done
}

install_packages() {
  [[ -f "${PACKAGES_FILE}" ]] || { log_error "Missing ${PACKAGES_FILE}"; exit 1; }

  # Fedora's own repos don't carry the Hyprland ecosystem, hyprmoncfg, or
  # Ghostty. Enable their COPRs before resolving packages.txt.
  ensure_coprs "sdegler/hyprland" "paolino/hyprmoncfg" "scottames/ghostty"

  local packages=() missing=() pkg
  # Strip comments and blank lines.
  while IFS= read -r pkg; do
    pkg="${pkg%%#*}"
    pkg="${pkg// /}"
    [[ -z "${pkg}" ]] && continue
    packages+=("${pkg}")
  done < "${PACKAGES_FILE}"

  for pkg in "${packages[@]}"; do
    rpm -q "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    log_success "All ${#packages[@]} dnf packages already installed."
  else
    log "Installing ${#missing[@]} dnf package(s): ${missing[*]}"
    # --setopt=install_weak_deps=False: this list is meant to be the exact,
    # curated set of packages installed — not that plus whatever every
    # package's Recommends happens to pull in transaction-wide (e.g. nwg-bar,
    # nwg-panel, and kitty have all been observed sneaking in this way).
    sudo dnf install -y --setopt=install_weak_deps=False "${missing[@]}"
    log_success "dnf packages installed."
  fi

  # Fedora's "development-tools" group is VCS/doc tooling (git, doxygen,
  # subversion); "c-development" is the actual build-essential equivalent
  # (gcc, gcc-c++, make, binutils, autoconf, automake, ...).
  if dnf group info c-development 2>/dev/null | grep -qE '^Installed\s*:\s*yes'; then
    log_success "C Development Tools group already installed."
  else
    log "Installing C Development Tools group (build-essential equivalent)..."
    sudo dnf group install -y c-development
    log_success "C Development Tools group installed."
  fi
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
  log "Installing gh CLI from official dnf repo..."
  # Per https://github.com/cli/cli/blob/trunk/docs/install_linux.md
  sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
  sudo dnf install -y gh
}

ensure_1password() {
  if command -v 1password >/dev/null 2>&1; then
    log_success "1Password already installed."
    return
  fi

  # 1Password is proprietary — not in Fedora's repos. Official dnf repo per
  # https://support.1password.com/install-linux/#rhel-fedora-or-centos
  log "Installing 1Password from the official dnf repo..."
  require_command curl "to fetch the 1Password signing key"

  sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
  sudo tee /etc/yum.repos.d/1password.repo >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey="https://downloads.1password.com/linux/keys/1password.asc"
EOF

  sudo dnf install -y 1password
  log_success "1Password installed."
}

ensure_google_chrome() {
  if command -v google-chrome-stable >/dev/null 2>&1; then
    log_success "Google Chrome already installed."
    return
  fi

  # Proprietary — not in Fedora's repos. Official dnf repo per
  # https://www.google.com/linuxrepositories/
  log "Installing Google Chrome from the official dnf repo..."
  sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
  sudo tee /etc/yum.repos.d/google-chrome.repo >/dev/null <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

  sudo dnf install -y google-chrome-stable
  log_success "Google Chrome installed."
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
  require_command fish "after dnf install"

  local fish_path
  fish_path="$(command -v fish)"
  local account_name="${USER:-$(id -un)}"

  if ! grep -qxF "${fish_path}" /etc/shells; then
    log "Adding ${fish_path} to /etc/shells."
    printf '%s\n' "${fish_path}" | sudo tee -a /etc/shells >/dev/null
  else
    log_success "fish already in /etc/shells."
  fi

  local login_shell
  login_shell="$(getent passwd "${account_name}" | cut -d: -f7)"
  if [[ "${login_shell}" != "${fish_path}" ]]; then
    log "Setting fish as default shell for ${account_name}."
    sudo chsh -s "${fish_path}" "${account_name}"
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

  if [[ -n "${existing_email}" ]]; then
    log_success "Git identity already configured (override email: ${existing_email})."
    return
  fi
  if [[ ! -t 0 ]]; then
    log_warn "Git identity needs setup, but bootstrap is not running interactively."
    log_info "Run shared/lib/git-profile.sh personal or work later."
    return
  fi

  log "Setting up Git identity..."
  "${SHARED_DIR}/lib/git-profile.sh"
}

main() {
  ensure_user_context
  ensure_fedora

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for Linux."

  install_packages
  ensure_gh
  ensure_1password
  ensure_google_chrome
  ensure_docker
  ensure_mise

  # gh auth comes BEFORE the fonts sync, which comes BEFORE link.sh:
  # linux/managed-links.sh only appends the font link when
  # shared/fonts/berkeley-mono exists, and a fresh interactive bootstrap should
  # get the fonts (and their link) in this same run. Both steps degrade
  # gracefully when auth is impossible (non-interactive: ensure_gh_auth warns
  # and returns, fonts.sh then warns and skips — re-run after gh auth login).
  log "Checking gh CLI authentication..."
  ensure_gh_auth

  log "Syncing licensed fonts from private repo..."
  "${SHARED_DIR}/lib/fonts.sh"

  log "Linking managed configs into ${HOME}..."
  "${SHARED_DIR}/lib/link.sh" linux

  log "Running Linux system tweaks..."
  "${LINUX_DIR}/setup.sh"

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
