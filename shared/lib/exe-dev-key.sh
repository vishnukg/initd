#!/usr/bin/env bash
set -euo pipefail

# Creates this machine's exe.dev key (~/.ssh/id_ed25519_exe, the IdentityFile
# the managed SSH config names for the dev box). Run from a platform bootstrap
# AFTER link.sh: it acts only when ~/.ssh/config is the managed link, which
# exists on personal machines alone - so a work machine gets no key and no
# output, by the same gate rather than a second copy of it.
#
# Registering the key cannot be automated: exe.dev asks for the account's
# email (`ssh exe.dev`) or a paste on its web page. A new key prints how.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

KEY="${HOME}/.ssh/id_ed25519_exe"

main() {
  [[ "$(readlink "${HOME}/.ssh/config" 2>/dev/null || true)" == "${ROOT_DIR}/shared/configs/ssh/.ssh/config" ]] || return 0

  if [[ -f "${KEY}" ]]; then
    log_success "exe.dev key present (${KEY})."
    return
  fi

  require_command ssh-keygen "to create the exe.dev key"
  mkdir -p -m 700 "${HOME}/.ssh"
  ssh-keygen -q -t ed25519 -N "" -C "${HOSTNAME%%.*} exe.dev" -f "${KEY}"
  log_success "Created this machine's exe.dev key (${KEY})."
  log_info "Register it with the existing account (docs/remote-dev-box.md, step 5):"
  log_info "  run 'ssh exe.dev' and give the SAME email (a different one makes a new account),"
  log_info "  or paste this line at https://exe.dev/user/security:"
  log_info "  $(cat "${KEY}.pub")"
}

main "$@"
