#!/usr/bin/env bash
set -euo pipefail

# Linux platform bootstrap. Invoked by the top-level dispatcher when uname=Linux.
# Targets Ubuntu 26.04+ (everything in packages.txt is in the official archive);
# other Debian-based distros work if their repos carry the same packages.

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

disable_snap() {
  if ! command -v snap >/dev/null 2>&1; then
    log_success "snapd already removed."
    return
  fi

  log "Removing snap packages and snapd..."
  # Remove snaps in dependency order: retry the full list until a pass
  # removes nothing more (leaf app snaps go first, base/runtime snaps last).
  local remaining prev_count=-1
  while true; do
    remaining=$(snap list 2>/dev/null | tail -n +2 | awk '{print $1}')
    [[ -z "${remaining}" ]] && break
    local count
    count=$(wc -l <<< "${remaining}")
    [[ "${count}" -eq "${prev_count}" ]] && break
    prev_count="${count}"
    while IFS= read -r s; do
      [[ -z "${s}" ]] && continue
      sudo snap remove --purge "${s}" 2>/dev/null || true
    done <<< "${remaining}"
  done

  sudo apt-get purge -y snapd

  # Pin snapd out so a later `apt upgrade`/meta-package pull never reinstalls it.
  sudo tee /etc/apt/preferences.d/nosnap.pref > /dev/null << 'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

  sudo rm -rf /var/cache/snapd /var/lib/snapd /var/snap /snap
  rm -rf "${HOME}/snap"
  log_success "snapd removed and blocked from reinstalling."
}

ensure_firefox() {
  if [[ -f /etc/apt/sources.list.d/mozilla.list ]]; then
    log_success "Firefox already installed from Mozilla's apt repo."
    return
  fi

  # Ubuntu's `firefox` apt package is a transitional stub that installs the
  # snap. Add Mozilla's official repo, pinned above the Ubuntu archive, so a
  # plain `apt install firefox` resolves to the real .deb.
  log "Adding Mozilla's official apt repo for Firefox..."
  require_command wget "to fetch the Mozilla signing key"

  sudo install -d -m 0755 /etc/apt/keyrings
  wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- \
    | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
    | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
  sudo tee /etc/apt/preferences.d/mozilla.pref > /dev/null << 'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

  sudo apt-get update -qq
  sudo apt-get install -y firefox
  log_success "Firefox installed from Mozilla's apt repo."
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

ensure_ghostty() {
  if command -v ghostty >/dev/null 2>&1; then
    log_success "ghostty already installed."
    return
  fi

  # Ubuntu 26.04+ ships ghostty in universe; older releases need the PPA.
  if apt-cache policy ghostty 2>/dev/null | grep -q 'Candidate: [0-9]'; then
    log "Installing ghostty from the Ubuntu archive..."
    sudo apt-get install -y ghostty
  else
    log "Installing ghostty from Ubuntu PPA (mkasberg/ghostty-ubuntu)..."
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu
    sudo apt-get update -qq
    sudo apt-get install -y ghostty
  fi
  log_success "ghostty installed."
}

ensure_1password() {
  if command -v 1password >/dev/null 2>&1; then
    log_success "1Password already installed."
    return
  fi

  # 1Password is proprietary — not in the Ubuntu archive. Official apt repo per
  # https://support.1password.com/install-linux/#debian-or-ubuntu
  log "Installing 1Password from the official apt repo..."
  require_command curl "to fetch the 1Password signing key"

  curl -sS --max-time 60 https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --yes --output /usr/share/keyrings/1password-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" \
    | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null

  # debsig verification policy (1Password's .deb packages are signature-checked).
  sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22 /usr/share/debsig/keyrings/AC2D62742012EA22
  curl -sS --max-time 60 https://downloads.1password.com/linux/debian/debsig/1password.pol \
    | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
  curl -sS --max-time 60 https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --yes --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

  sudo apt-get update -qq
  sudo apt-get install -y 1password
  log_success "1Password installed."
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
  ensure_debian

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for Linux."

  disable_snap
  install_packages
  ensure_gh
  ensure_ghostty
  ensure_1password
  ensure_firefox
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
