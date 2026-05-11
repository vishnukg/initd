#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${ROOT_DIR}/scripts/logging.sh"

SSH_CONFIG="${HOME}/.ssh/config"

personal_block() {
  cat <<'EOF'
# BEGIN initd-github
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_github_personal
  AddKeysToAgent yes
  UseKeychain yes
# END initd-github
EOF
}

work_block() {
  cat <<'EOF'
# BEGIN initd-github
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_github_work
  AddKeysToAgent yes
  UseKeychain yes

# Personal GitHub — use git@github-personal:vishnukg/<repo>.git
Host github-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_github_personal
  AddKeysToAgent yes
  UseKeychain yes
# END initd-github
EOF
}

# Print all lines up to and including the last non-empty line (strips trailing blank lines).
strip_trailing_blank() {
  awk 'NF { p = NR } { a[NR] = $0 } END { for (i = 1; i <= p; i++) print a[i] }'
}

update_ssh_config() {
  local profile="$1"
  local block

  case "${profile}" in
    personal) block="$(personal_block)" ;;
    work)     block="$(work_block)" ;;
    *) log_error "ssh-config: unknown profile '${profile}'"; exit 1 ;;
  esac

  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  touch "${SSH_CONFIG}"
  chmod 600 "${SSH_CONFIG}"

  # Strip the existing initd-managed block from the file.
  local existing
  existing="$(awk '
    /^# BEGIN initd-github/ { skip=1; next }
    /^# END initd-github/   { skip=0; next }
    !skip { print }
  ' "${SSH_CONFIG}" | strip_trailing_blank)"

  # Reassemble: existing content + blank separator + new block.
  {
    if [[ -n "${existing}" ]]; then
      printf '%s\n\n' "${existing}"
    fi
    printf '%s\n' "${block}"
  } > "${SSH_CONFIG}"
}

# Add a key to the macOS Keychain so it's loaded into the agent automatically on login.
add_to_keychain() {
  local key_path="$1"
  local label="$2"

  if [[ ! -f "${key_path}" ]]; then
    log_warn "${label} key not found: ${key_path}"
    log_info "Copy your ${label} GitHub key there and re-run this script."
    return
  fi

  if ssh-add --apple-use-keychain "${key_path}" 2>/dev/null; then
    log_success "${label} key added to macOS Keychain (auto-loaded on login)."
  else
    log_warn "Could not add ${label} key to Keychain — add it manually: ssh-add --apple-use-keychain ${key_path}"
  fi
}

main() {
  local profile="${1:-personal}"

  update_ssh_config "${profile}"
  log_success "~/.ssh/config updated for ${profile} GitHub profile."

  add_to_keychain "${HOME}/.ssh/id_github_personal" "personal"
  if [[ "${profile}" == "work" ]]; then
    add_to_keychain "${HOME}/.ssh/id_github_work" "work"
    log_info "Clone initd with:          git clone git@github-personal:vishnukg/initd.git"
    log_info "Or update existing remote: git remote set-url origin git@github-personal:vishnukg/initd.git"
  fi
}

main "$@"
