#!/usr/bin/env bash

# Shared by bootstrap and update; operates only on a disposable Brewfile copy.
# Drop a cask from the temp Brewfile when its app already lives outside Homebrew,
# so brew bundle doesn't fail trying to install into an already-occupied path.
strip_cask_if_app_exists() {
  local cask="$1" app="$2"

  if [[ -d "${app}" ]] && ! brew list --cask "${cask}" >/dev/null 2>&1; then
    log_warn "Skipping ${cask} cask: ${app} already exists outside Homebrew."
    local filter_status=0
    grep -Ev "^[[:space:]]*cask[[:space:]]+[\"']${cask}[\"'][[:space:]]*(#.*)?$" \
      "${brewfile_tmp}" > "${brewfile_tmp}.tmp" || filter_status=$?
    # grep returns 1 when the last entry was removed; that is a valid empty
    # Brewfile. A read/filter error must preserve the original instead.
    if (( filter_status > 1 )); then return "${filter_status}"; fi
    mv "${brewfile_tmp}.tmp" "${brewfile_tmp}"
  fi
}

prepare_brewfile() {
  cp "${BREWFILE}" "${brewfile_tmp}"
  local entry cask app directory
  local applications_dir="${1:-/Applications}"
  # Keep existing apps under their current owner's control. Check both common
  # install locations; fresh machines retain every cask in the bundle.
  for entry in '1password:1Password.app' 'betterdisplay:BetterDisplay.app' \
      'google-chrome:Google Chrome.app' 'ghostty:Ghostty.app' \
      'kitty:kitty.app' 'iterm2:iTerm.app'; do
    cask="${entry%%:*}"
    app="${entry#*:}"
    for directory in "${applications_dir}" "${HOME}/Applications"; do
      strip_cask_if_app_exists "${cask}" "${directory}/${app}"
    done
  done
}
