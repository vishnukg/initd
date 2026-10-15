#!/usr/bin/env bash

# Headless VM managed symlinks. Unlike macos/ and linux/, this platform REMOVES
# shared entries rather than appending: the shared list carries desktop-side
# configs (terminals, Colima, wallpapers) that a remote box never uses. The
# laptop's terminal renders the VM's tmux, so its config stays on the laptop.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing vm/managed-links.sh}"
: "${MANAGED_LINKS:?MANAGED_LINKS must be initialised by shared/managed-links.sh first}"

VM_SKIPPED_LINKS=(
  "${HOME}/.colima/_templates/default.yaml"
  "${HOME}/.config/ghostty"
  "${HOME}/.config/kitty"
  "${HOME}/.config/kitty-dev-box.conf"
  "${HOME}/.local/share/wallpapers"
  # The laptop's config for reaching the VM; the VM has no use for it.
  "${HOME}/.ssh/config"
)

vm_links=()
for vm_entry in "${MANAGED_LINKS[@]}"; do
  vm_keep=1
  for vm_skip in "${VM_SKIPPED_LINKS[@]}"; do
    [[ "${vm_entry}" == "${vm_skip}:"* ]] && vm_keep=0
  done
  [[ "${vm_keep}" == 1 ]] && vm_links+=("${vm_entry}")
done
MANAGED_LINKS=("${vm_links[@]}")
unset vm_links vm_entry vm_keep vm_skip
