#!/usr/bin/env bash
set -euo pipefail

# Writes the PUBLIC half of the exe.dev key to ~/.ssh/id_ed25519_exe.pub, the
# IdentityFile the managed SSH config names for the dev box. The private key
# lives only in 1Password - one "exe.dev" SSH Key item shared by every personal
# machine, served by the app's SSH agent - so nothing is generated or
# registered per machine. ssh needs the public half on disk to ask the agent
# for that one key (IdentitiesOnly) instead of offering every key in the vault.
#
# Run from a platform bootstrap AFTER link.sh: it acts only when ~/.ssh/config
# is the managed link, which exists on personal machines alone - so a work
# machine gets no key and no output, by the same gate rather than a second
# copy of it. Re-reads the agent every run, so a rotated key lands here too.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

AGENT="${HOME}/.1password/agent.sock"
PUB="${HOME}/.ssh/id_ed25519_exe.pub"
ITEM="exe.dev"

main() {
  [[ "$(readlink "${HOME}/.ssh/config" 2>/dev/null || true)" == "${ROOT_DIR}/shared/configs/ssh/.ssh/config" ]] || return 0

  # The agent names each key by its item title. ssh-add exits 1 with no keys.
  local key
  key="$(SSH_AUTH_SOCK="${AGENT}" ssh-add -L 2>/dev/null | awk -v item="${ITEM}" '$3 == item { print; exit }' || true)"

  if [[ -n "${key}" ]]; then
    mkdir -p -m 700 "${HOME}/.ssh"
    # 0600 although public: when the agent is locked ssh tries this path as a
    # private key, and a 0644 file buys a wall of "UNPROTECTED" warnings.
    printf "%s\n" "${key}" > "${PUB}"
    chmod 600 "${PUB}"
    log_success "exe.dev public key written from 1Password (${PUB})."
  elif [[ -f "${PUB}" ]]; then
    log_warn "1Password's SSH agent is not serving '${ITEM}'; keeping ${PUB}. Unlock 1Password before 'ssh dev'."
  else
    log_warn "No exe.dev key: 1Password's SSH agent is not serving '${ITEM}', so 'ssh dev' will fail."
    log_info "  1Password > Settings > Developer > Use the SSH agent, with the '${ITEM}' SSH Key"
    log_info "  item in the Private vault (docs/remote-dev-box.md), then re-run shared/lib/exe-dev-key.sh."
  fi

  # Before 1Password held it, each machine generated its own key file here.
  if [[ -f "${HOME}/.ssh/id_ed25519_exe" ]]; then
    log_warn "An old on-disk exe.dev key is still at ~/.ssh/id_ed25519_exe. Remove it from"
    log_warn "  the account ('ssh exe.dev ssh-key list'), then delete the file."
  fi
}

main "$@"
