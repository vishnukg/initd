#!/usr/bin/env bash
set -euo pipefail

# Writes the PUBLIC halves of the 1Password SSH keys the managed SSH config
# names: the "exe.dev" item to ~/.ssh/id_ed25519_exe.pub and the "GitHub" item
# to ~/.ssh/id_ed25519_github.pub (also git's commit signing key). The private
# keys live only in 1Password - one item each, shared by every personal
# machine and served by the app's SSH agent - so nothing is generated or
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

# item title : public key file : the on-disk private key it replaced
KEYS=(
  "exe.dev:id_ed25519_exe.pub:id_ed25519_exe"
  "GitHub:id_ed25519_github.pub:id_ed25519"
)

main() {
  [[ "$(readlink "${HOME}/.ssh/config" 2>/dev/null || true)" == "${ROOT_DIR}/shared/configs/ssh/.ssh/config" ]] || return 0

  # The agent names each key by its item title. ssh-add exits 1 with no keys.
  local listing
  listing="$(SSH_AUTH_SOCK="${AGENT}" ssh-add -L 2>/dev/null || true)"

  local entry item pub legacy key
  for entry in "${KEYS[@]}"; do
    IFS=: read -r item pub legacy <<< "${entry}"
    pub="${HOME}/.ssh/${pub}"
    # Titles match case-insensitively: "GitHub" and "Github" are the same item.
    key="$(awk -v item="${item}" 'tolower($3) == tolower(item) { print; exit }' <<< "${listing}")"

    if [[ -n "${key}" ]]; then
      mkdir -p -m 700 "${HOME}/.ssh"
      # 0600 although public: when the agent is locked ssh tries this path as a
      # private key, and a 0644 file buys a wall of "UNPROTECTED" warnings.
      printf "%s\n" "${key}" > "${pub}"
      chmod 600 "${pub}"
      log_success "${item} public key written from 1Password (${pub})."
    elif [[ -f "${pub}" ]]; then
      log_warn "1Password's SSH agent is not serving '${item}'; keeping ${pub}. Unlock 1Password before using it."
    else
      log_warn "No ${item} key: 1Password's SSH agent is not serving '${item}'."
      log_info "  1Password > Settings > Developer > Use the SSH agent, with the '${item}' SSH Key"
      log_info "  item in the Private vault (docs/remote-dev-box.md), then re-run shared/lib/ssh-keys.sh."
    fi

    # Before 1Password held it, each machine generated its own key file here.
    if [[ -f "${HOME}/.ssh/${legacy}" ]]; then
      log_warn "An old on-disk ${item} key is still at ~/.ssh/${legacy}. Remove it from"
      log_warn "  the account it is registered with, then delete the file."
    fi
  done
}

main "$@"
