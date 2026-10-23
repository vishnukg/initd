#!/usr/bin/env bash
set -euo pipefail

# Headless VM bootstrap: the dev toolchain with no desktop. Targets Ubuntu
# 24.04+ (apt) — exe.dev's default "exeuntu" image in particular. The
# top-level dispatcher only runs it when named, since a VM and the Fedora
# desktop are both just Linux to uname:
#
#   bash bootstrap.sh vm      # or directly: bash vm/bootstrap.sh
#
# Run it interactively (`ssh -t`), so gh auth and the Git identity can prompt:
# mise resolves its ~50 GitHub-hosted tools through `gh auth token`, and an
# unauthenticated install runs into GitHub's 60-requests-an-hour API limit.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="${ROOT_DIR}/vm"
SHARED_DIR="${ROOT_DIR}/shared"

PACKAGES_FILE="${VM_DIR}/packages.txt"

export BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S).$$}"

# shellcheck disable=SC1091
source "${SHARED_DIR}/lib/logging.sh"

APT_UPDATED=0

ensure_user_context() {
  if [[ "${EUID}" == "0" ]]; then
    log_error "Do not run bootstrap with sudo. It manages files and the login shell for your normal user."
    exit 1
  fi
}

ensure_ubuntu() {
  local id=""
  # shellcheck disable=SC1091
  [[ -f /etc/os-release ]] && id="$(. /etc/os-release && printf '%s' "${ID:-}")"
  if [[ "${id}" != "ubuntu" ]]; then
    log_error "vm/bootstrap.sh only supports Ubuntu (found: ${id:-unknown})."
    exit 1
  fi
  require_command apt-get "to install Ubuntu packages"
}

apt_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

# One `apt-get update` per run, however many steps need a fresh index.
apt_update() {
  [[ "${APT_UPDATED}" == 1 ]] && return
  sudo apt-get update -q
  APT_UPDATED=1
}

apt_install() {
  apt_update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends "$@"
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
    apt_installed "${pkg}" || missing+=("${pkg}")
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    log_success "All ${#packages[@]} apt packages already installed."
  else
    log "Installing ${#missing[@]} apt package(s): ${missing[*]}"
    apt_install "${missing[@]}"
    log_success "apt packages installed."
  fi
}

# Roots distrusted after a CA key compromise, by their /etc/ssl/certs name.
# emSign ECC Root CA - G3: eMudhra intermediates whose private keys can be
# recovered from the public certificates (https://emudhra.we-have-a-problem.com/,
# LP #2171507); Ubuntu dropped it in ca-certificates 20260816ubuntu0.24.04.1.
DISTRUSTED_ROOTS=(emSign_ECC_Root_CA_-_G3)
CERTS_DIR=/etc/ssl/certs

# install_packages skips anything already present, and every image ships
# ca-certificates - so without this a new VM keeps whatever trust store its
# image was built with, however stale. Runs before the first curl.
ensure_trust_store() {
  log "Upgrading ca-certificates to the archive's latest..."
  apt_update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --only-upgrade ca-certificates

  local root trusted=()
  for root in "${DISTRUSTED_ROOTS[@]}"; do
    [[ -e "${CERTS_DIR}/${root}.pem" ]] && trusted+=("${root}")
  done
  if [[ "${#trusted[@]}" -gt 0 ]]; then
    log_error "The system trust store still trusts compromised root(s): ${trusted[*]}"
    log_info "Upgrade ca-certificates (or blocklist them with ! in /etc/ca-certificates.conf and run update-ca-certificates), then re-run."
    exit 1
  fi
  log_success "System trust store is current."
}

ensure_fish_ppa() {
  # Ubuntu 24.04's own fish is 3.7; the shared config is written against 4.x.
  local major=0
  command -v fish >/dev/null 2>&1 && major="$(fish --version | sed -E 's/[^0-9]*([0-9]+).*/\1/')"
  if [[ "${major}" -ge 4 ]]; then
    log_success "fish $(fish --version | awk '{print $NF}') already installed."
    return
  fi

  log "Installing fish 4 from the fish-shell/release-4 PPA..."
  command -v add-apt-repository >/dev/null 2>&1 || apt_install software-properties-common
  sudo add-apt-repository -y ppa:fish-shell/release-4
  APT_UPDATED=0
  apt_install fish
  log_success "fish installed."
}

ensure_docker() {
  local account_name="${USER:-$(id -un)}"

  # exeuntu ships Docker already; only a bare Ubuntu needs installing.
  if command -v docker >/dev/null 2>&1; then
    log_success "Docker already installed."
  else
    log "Installing Docker from Ubuntu's repos..."
    apt_install docker.io docker-compose-v2 docker-buildx
    log_success "Docker installed."
  fi

  if id -nG "${account_name}" | grep -qw docker; then
    log_success "${account_name} already belongs to the docker group."
  else
    sudo usermod -aG docker "${account_name}"
    log_warn "Added ${account_name} to the docker group. Reconnect before using Docker without sudo."
  fi
}

ensure_gh() {
  if command -v gh >/dev/null 2>&1; then
    log_success "gh CLI already installed."
    return
  fi
  # Per https://github.com/cli/cli/blob/trunk/docs/install_linux.md.
  log "Installing gh CLI from the official apt repo..."
  local keyring=/etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL --max-time 60 https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee "${keyring}" >/dev/null
  sudo chmod go+r "${keyring}"
  printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" "${keyring}" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  APT_UPDATED=0
  apt_install gh
  log_success "gh CLI installed."
}

ensure_mise() {
  # mise.run installs to ~/.local/bin. Put it on PATH before the check so a
  # re-run from a shell that lacks it doesn't reinstall over the existing one.
  export PATH="${HOME}/.local/bin:${PATH}"
  if command -v mise >/dev/null 2>&1; then
    log_success "mise already installed."
    return
  fi

  require_command curl "to install mise"
  log "Installing mise from mise.run..."
  curl -fsSL --max-time 60 https://mise.run | sh
  require_command mise "after mise.run install"
}

ensure_gh_auth() {
  if gh auth token >/dev/null 2>&1; then
    log_success "gh auth check done."
    return
  fi
  if [[ ! -t 0 ]]; then
    log_warn "gh CLI is not authenticated, and bootstrap is not running interactively."
    log_info "Run gh auth login later, then re-run vm/bootstrap.sh."
    return
  fi
  log "Authenticating gh CLI..."
  gh auth login
}

# GitHub's published ed25519 host key fingerprint:
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
GITHUB_ED25519_FINGERPRINT="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"

# Git over SSH with a key that belongs to this box alone, so it can be revoked
# on GitHub without touching any other machine. `gh auth login` alone is not
# enough: ~/.gitconfig is the tracked shared config, so gh's credential helper
# never lands in it and HTTPS git stays read-only.
ensure_github_ssh() {
  local key="${HOME}/.ssh/id_ed25519"
  mkdir -p -m 700 "${HOME}/.ssh"

  if [[ ! -f "${key}" ]]; then
    log "Generating this VM's GitHub SSH key..."
    ssh-keygen -q -t ed25519 -N "" -C "${USER:-$(id -un)}@$(hostname) github" -f "${key}"
  fi

  if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    local scanned fingerprint
    scanned="$(ssh-keyscan -t ed25519 github.com 2>/dev/null)"
    fingerprint="$(ssh-keygen -lf - <<< "${scanned}" | awk '{print $2}')"
    if [[ "${fingerprint}" != "${GITHUB_ED25519_FINGERPRINT}" ]]; then
      log_error "github.com host key fingerprint ${fingerprint:-<none>} does not match GitHub's published one."
      return 1
    fi
    printf '%s\n' "${scanned}" >> "${HOME}/.ssh/known_hosts"
    log_success "Trusted github.com's verified host key."
  fi

  # GitHub answers -T with exit 1 either way; only the greeting proves the key
  # works. Captured first, not piped: under pipefail ssh's 1 would sink grep's 0.
  local greeting
  greeting="$(ssh -T -o BatchMode=yes git@github.com </dev/null 2>&1 || true)"
  if [[ "${greeting}" == *'successfully authenticated'* ]]; then
    log_success "GitHub accepts this VM's SSH key."
  elif [[ ! -t 0 ]]; then
    log_warn "This VM's SSH key is not on GitHub, and bootstrap is not running interactively."
    log_info "Add ${key}.pub at github.com/settings/keys, then re-run vm/bootstrap.sh."
    return
  else
    log "Adding this VM's SSH key to GitHub (gh asks once for the admin:public_key scope)..."
    gh auth refresh -h github.com -s admin:public_key
    gh ssh-key add "${key}.pub" --title "$(hostname) (initd vm)" --type authentication
  fi

  gh config set git_protocol ssh
  local origin
  origin="$(git -C "${ROOT_DIR}" remote get-url origin 2>/dev/null || true)"
  if [[ "${origin}" == https://github.com/* ]]; then
    origin="${origin#https://github.com/}"
    git -C "${ROOT_DIR}" remote set-url origin "git@github.com:${origin%.git}.git"
    log_success "Switched the initd checkout's origin to SSH."
  fi
}

ensure_fish() {
  require_command fish "after the fish install"

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

  # stdin is /dev/null because fisher reads plugin names from any non-tty stdin
  # and waits for EOF: a piped or scripted bootstrap would hang here forever.
  log "Syncing fisher plugins..."
  GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)" fish -c "
    if not functions -q fisher
      curl -fsSL --max-time 30 https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
      fisher install jorgebucaran/fisher
    end
    fisher update
  " </dev/null
}

# node@lts is named explicitly, as in shared/lib/link.sh: a bare
# `mise exec --` first installs every missing tool in the global config.
run_node() {
  mise -C "${ROOT_DIR}" exec node@lts -- node "$@"
}

setup_git_profile() {
  local local_gitconfig="${SHARED_DIR}/configs/git/local.gitconfig"
  local existing_email
  existing_email="$(git config --file "${local_gitconfig}" user.email 2>/dev/null || true)"

  if [[ -n "${existing_email}" ]]; then
    log_success "Git identity already configured (email: ${existing_email})."
    return
  fi
  if [[ ! -t 0 ]]; then
    log_warn "Git identity needs setup, but bootstrap is not running interactively."
    log_info "Run node shared/lib/git-profile.mjs personal or work later."
    return
  fi

  log "Setting up Git identity..."
  run_node "${SHARED_DIR}/lib/git-profile.mjs"
}

main() {
  ensure_user_context
  ensure_ubuntu

  log_info "Backups for unmanaged configs will go under ${BACKUP_ROOT}"
  log "Starting initd bootstrap for a headless VM."

  install_packages
  ensure_trust_store
  ensure_fish_ppa
  ensure_docker
  ensure_gh
  ensure_mise

  # Before mise install: github.credential_command is `gh auth token`.
  log "Checking gh CLI authentication..."
  ensure_gh_auth

  log "Checking GitHub SSH access..."
  ensure_github_ssh

  log "Linking managed configs into ${HOME}..."
  "${SHARED_DIR}/lib/link.sh" vm

  log "Configuring Claude Code's statusLine hook for the tmux usage pill..."
  run_node "${SHARED_DIR}/lib/claude-statusline.mjs"

  log "Configuring the Antigravity CLI statusLine hook for the tmux usage pill..."
  run_node "${SHARED_DIR}/lib/agy-statusline.mjs"

  log "Ensuring fish shell is configured..."
  ensure_fish

  log "Trusting shared mise config."
  mise trust "${SHARED_DIR}/configs/mise/.config/mise/config.toml"

  log "Installing shared runtimes and LSP tooling with mise..."
  mise -C "${ROOT_DIR}" install --yes

  setup_git_profile

  echo
  log_success "initd finished for the VM. Reconnect to land in fish + tmux."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
