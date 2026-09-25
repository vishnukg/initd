#!/usr/bin/env bash
set -euo pipefail

# Linux system tweaks and config glue that don't fit the standard symlink flow:
#   - Fonts (FiraCode Nerd Font, Symbols Nerd Font)
#   - System fixes that need sudo (unused ModemManager/abrt/rsyslog off,
#     `video` group for the backlight keys)
#   - Session/user-unit state: masking the hypridle/hyprpaper units this repo
#     autostarts from hyprland.lua instead, enabling hyprmoncfgd and the
#     night-light schedule timer
#   - gsettings that GTK/portal apps read (theme, fonts, cursor, keyboard),
#     kept in sync with hyprland.lua so GNOME and Hyprland feel the same
#   - Session scripts linked to absolute ~/.config/ paths (the shell uses them)
#   - Firefox profile glue (profile path is dynamic)
#
# Wayland/Hyprland only — the old X11 fixes (xorg TearFree, autorandr, picom,
# xsettingsd, Xresources) are gone; Hyprland handles compositing, monitors and
# per-monitor scale natively.
#
# Safe to re-run. Standard ~/.config symlinks are handled by shared/lib/link.sh.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX_DIR="${ROOT_DIR}/linux"
CONFIGS_DIR="${LINUX_DIR}/configs"
SCRIPTS_DIR="${LINUX_DIR}/scripts"

# setup.sh is also useful on its own, so give special-case links the same
# recoverable backup behaviour as shared/lib/link.sh.
export BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.config/initd-backups/$(date +%Y%m%d%H%M%S).$$}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

# ── Fonts ─────────────────────────────────────────────────────────────────────
install_firacode_nerd_font() (
  local font_dir="${HOME}/.local/share/fonts/FiraCode"

  if ls "${font_dir}"/*.ttf >/dev/null 2>&1; then
    log_success "FiraCode Nerd Font already installed."
    return
  fi

  require_command curl "to download Nerd Fonts"
  require_command unzip "to extract Nerd Fonts"

  mkdir -p "${font_dir}"
  local archive
  archive="$(mktemp "${TMPDIR:-/tmp}/initd-firacode.XXXXXX")"
  trap 'rm -f "${archive}"' EXIT
  log "Downloading FiraCode Nerd Font..."
  curl -fL --progress-bar --max-time 300 \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" \
    -o "${archive}"
  unzip -q -o "${archive}" "*.ttf" -d "${font_dir}"
  fc-cache -f "${font_dir}" >/dev/null
  log_success "FiraCode Nerd Font installed."
)

install_symbols_nerd_font() (
  # Berkeley Mono (kitty's font) carries no Nerd Font icon glyphs, so kitty's
  # symbol_map points at this family. Ghostty no longer needs it — it runs the
  # patched FiraCode Nerd Font build, which carries the icons in-family — but
  # this stays installed because kitty still depends on it. Fedora packages no
  # equivalent; macOS gets it from the font-symbols-only-nerd-font cask in
  # macos/Brewfile. Both builds are installed: the non-Mono one is what
  # the configs name (natural-width icons), the Mono one is on hand for
  # single-cell glyphs like powerline separators.
  local font_dir="${HOME}/.local/share/fonts/SymbolsNerdFont"

  if ls "${font_dir}"/*.ttf >/dev/null 2>&1; then
    log_success "Symbols Nerd Font already installed."
    return
  fi

  require_command curl "to download Nerd Fonts"
  require_command unzip "to extract Nerd Fonts"

  mkdir -p "${font_dir}"
  local archive
  archive="$(mktemp "${TMPDIR:-/tmp}/initd-symbols.XXXXXX")"
  trap 'rm -f "${archive}"' EXIT
  log "Downloading Symbols Nerd Font..."
  curl -fL --progress-bar --max-time 300 \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip" \
    -o "${archive}"
  unzip -q -o "${archive}" "*.ttf" -d "${font_dir}"
  fc-cache -f "${font_dir}" >/dev/null
  log_success "Symbols Nerd Font installed."
)

# ── System fixes ──────────────────────────────────────────────────────────────
disable_unused_daemons() {
  # Idle background daemons this machine gets nothing from. Each is checked
  # first so sudo is only invoked when something actually needs disabling.
  #   ModemManager — no cellular modem on this hardware (mmcli -L finds none);
  #                  it is a NetworkManager-optional plugin, safe to drop.
  #   abrt*        — Fedora's crash reporter: abrtd plus three journal/oops
  #                  watchers (~57 MB resident). Only useful for filing Fedora
  #                  bug reports, which this machine does not do.
  #   rsyslog      — duplicates the journal into /var/log/messages (~28 MB);
  #                  journalctl is the log here.
  local unit state to_disable=()
  for unit in ModemManager.service \
              abrtd.service abrt-journal-core.service abrt-oops.service \
              abrt-xorg.service abrt-vmcore.service \
              rsyslog.service; do
    # Absent units can print nothing to stdout; do not pass them to disable,
    # whose failure would abort the rest of setup under set -e.
    [[ "$(systemctl show -p LoadState --value "${unit}" 2>/dev/null)" == loaded ]] || continue
    state="$(systemctl is-enabled "${unit}" 2>/dev/null || true)"
    if [[ ! "${state}" =~ ^(disabled|masked)$ ]] || systemctl is-active --quiet "${unit}"; then
      to_disable+=("${unit}")
    fi
  done

  if [[ "${#to_disable[@]}" -eq 0 ]]; then
    log_success "Unused daemons already disabled (ModemManager, abrt, rsyslog)."
  else
    log "Disabling unused daemons: ${to_disable[*]}"
    sudo systemctl disable --now "${to_disable[@]}" >/dev/null 2>&1
    log_success "Disabled ${#to_disable[@]} unused daemon(s)."
  fi

  # packagekit — D-Bus system-activated (static unit, no [Install] section, so
  # `disable` alone doesn't stop it respawning). Backs gnome-software/Discover
  # and the codec/font auto-install prompts, neither used here since packages
  # are managed directly via dnf5/COPR; idles at 140-170 MB once activated.
  # `mask` (not `disable`) is required to actually block D-Bus activation.
  if [[ "$(systemctl is-enabled packagekit.service 2>/dev/null)" == masked ]]; then
    log_success "packagekit already masked."
  else
    log "Masking packagekit (unused, D-Bus-activated at ~150 MB)."
    sudo systemctl mask --now packagekit.service >/dev/null 2>&1
    log_success "Masked packagekit."
  fi
}

# ── Hyprland session ──────────────────────────────────────────────────────────
check_hyprland_session() {
  # Fedora's hyprland package ships the GDM session entry; verify it's there so
  # the login screen actually offers Hyprland next to GNOME.
  if [[ -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    log_success "Hyprland session available at the login screen."
  else
    log_warn "No /usr/share/wayland-sessions/hyprland.desktop — is the hyprland package installed?"
  fi
}

mask_desktop_user_units() {
  # hypridle/hyprpaper's upstream systemd user units may be enabled at
  # graphical-session.target, so they also launch inside GNOME sessions
  # (where hyprpaper segfaults) and race the hl.on("hyprland.start", ...)
  # autostart block in hyprland.lua under Hyprland. This repo owns autostart
  # via that block, so mask the units at the user level.
  local unit
  for unit in hypridle.service hyprpaper.service; do
    if [[ "$(systemctl --user is-enabled "${unit}" 2>/dev/null)" == "masked" ]]; then
      log_success "${unit} already masked."
    else
      systemctl --user mask "${unit}" >/dev/null 2>&1
      log_success "Masked ${unit} (autostarted via hyprland.lua instead)."
    fi
  done
}

enable_hyprmoncfg() {
  if ! command -v hyprmoncfgd >/dev/null 2>&1; then
    log_warn "hyprmoncfgd not found; skipping monitor profile service."
    return
  fi
  # Start it from graphical-session.target, not the packaged default.target:
  # that target is reached (via initd-hyprland-session.service) only once
  # Hyprland is up and the session env is imported, so the daemon's first
  # apply succeeds instead of failing and waiting for a poll. The managed
  # drop-in adds ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland so GNOME
  # sessions, which also reach that target, never start it.
  local wants="${HOME}/.config/systemd/user/graphical-session.target.wants/hyprmoncfgd.service"
  local default_want="${HOME}/.config/systemd/user/default.target.wants/hyprmoncfgd.service"
  systemctl --user daemon-reload
  if [[ -L "${wants}" && ! -e "${default_want}" ]]; then
    log_success "hyprmoncfgd already wired to graphical-session.target."
  else
    [[ -e "${default_want}" ]] && systemctl --user disable hyprmoncfgd.service >/dev/null 2>&1
    systemctl --user add-wants graphical-session.target hyprmoncfgd.service >/dev/null 2>&1
    log_success "hyprmoncfgd wired to graphical-session.target (Hyprland-only)."
  fi
  systemctl --user start hyprmoncfgd.service >/dev/null 2>&1 || true
}

enable_night_light_schedule() {
  # Units are managed links (linux/managed-links.sh). The timer fires `auto`
  # at 07:00 and 19:00; the oneshot is also wanted by graphical-session.target
  # so a login inside the warm window comes up warm. Start the oneshot now so
  # the current schedule applies without waiting for a boundary.
  systemctl --user daemon-reload
  systemctl --user enable --now night-light-schedule.timer >/dev/null 2>&1
  systemctl --user enable night-light-schedule.service >/dev/null 2>&1
  systemctl --user start night-light-schedule.service >/dev/null 2>&1 || true
  log_success "Night-light schedule enabled (warm 19:00-07:00)."
}

# Filesystem work runs through mise even before Node is on PATH. node@lts is
# named explicitly, as in shared/lib/link.sh: a bare `mise exec --` installs
# every missing tool in the global config first, so on a fresh machine this
# step would silently run the whole toolchain install (and abort setup if any
# one tool failed) long before bootstrap's own `mise install`.
run_node() {
  mise -C "${ROOT_DIR}" exec node@lts -- node "$@"
}

configure_links() {
  run_node "${SCRIPTS_DIR}/config-links.mjs"
}

configure_firefox() {
  run_node "${SCRIPTS_DIR}/firefox-profile.mjs" setup
}

configure_chrome() {
  run_node "${SCRIPTS_DIR}/chrome-profile.mjs"
}

apply_gsettings_theme() {
  # GTK3 apps read gtk-3.0/settings.ini, but GTK4/libadwaita apps on Wayland
  # get their theme through xdg-desktop-portal, which reads gsettings/dconf.
  # Keep both in sync or modern apps silently fall back to Fedora's Adwaita.
  if ! command -v gsettings >/dev/null 2>&1; then
    log_warn "gsettings not available — skipping theme sync."
    return
  fi
  gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
  gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
  gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
  # No Fedora package ships the DMZ cursors used on the old Ubuntu machine;
  # Adwaita is always present, no extra package needed.
  gsettings set org.gnome.desktop.interface cursor-theme "Adwaita"
  # 56 (the old laptop's value) was oversized on this machine's display; 24 is
  # Fedora/GNOME's own out-of-box default. hyprland.lua's hl.env("XCURSOR_SIZE", ...)
  # is what actually controls the on-screen cursor under Hyprland itself
  # (this gsetting only affects GTK apps) — keep the two in sync.
  gsettings set org.gnome.desktop.interface cursor-size 24
  # rsms-inter-fonts is installed by linux/bootstrap.sh. Keep GTK3, GTK4, and
  # the fontconfig generic sans-serif alias on the same high-quality UI font.
  gsettings set org.gnome.desktop.interface font-name "Inter 11"
  gsettings set org.gnome.desktop.interface document-font-name "Inter 12"
  gsettings set org.gnome.desktop.interface monospace-font-name "FiraCode Nerd Font 11"
  # Grayscale AA is stable across Wayland fractional scales and monitor
  # orientations; RGB subpixel AA can acquire colored fringes after scaling.
  gsettings set org.gnome.desktop.interface font-antialiasing "grayscale"
  gsettings set org.gnome.desktop.interface font-hinting "slight"
  gsettings set org.gnome.desktop.interface font-rgba-order "rgb"
  log_success "gsettings theme and fonts synced (grayscale AA, slight hinting)."
}

apply_gsettings_keyboard() {
  # Mirror hyprland.lua input settings in GNOME so both sessions feel the
  # same: caps lock as ctrl (kb_options = ctrl:nocaps) and key repeat
  # (repeat_delay = 350, repeat_rate = 30/s → interval 1000/30 ≈ 33ms).
  if ! command -v gsettings >/dev/null 2>&1; then
    log_warn "gsettings not available — skipping keyboard sync."
    return
  fi
  gsettings set org.gnome.desktop.input-sources xkb-options "['ctrl:nocaps']"
  gsettings set org.gnome.desktop.peripherals.keyboard delay 350
  gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 33
  log_success "gsettings keyboard synced (ctrl:nocaps, delay 350, interval 33ms)."
}

add_user_to_video_group() {
  # /sys/class/backlight/*/brightness is root:video — membership is required
  # for the brightnessctl keybinds (XF86MonBrightness*) to work.
  local account_name="${USER:-$(id -un)}"
  if id -nG "${account_name}" | grep -qw video; then
    log_success "User already in video group (backlight control)."
    return
  fi
  log "Adding ${account_name} to video group (brightness keys)..."
  sudo usermod -aG video "${account_name}"
  log_warn "Log out and back in for the video group to take effect."
}

# ── Service restarts (apply config changes without a reboot) ─────────────────
restart_dunst() {
  if pgrep -x dunst >/dev/null 2>&1; then
    pkill -x dunst; sleep 0.1
    dunst >/dev/null 2>&1 &
    disown
    log "dunst restarted."
  fi
}

usage() {
  cat <<EOF
Usage: ${0##*/} [--firefox-only | --chrome-only]

Apply Linux system tweaks and managed configuration.

Options:
  --chrome-only  Refresh Chrome interface scaling, page zoom and font sizes.
                  Close Chrome first to allow profile settings to be updated.
  --firefox-only  Refresh only the Firefox profile glue (userChrome.css,
                  user.js, default zoom) without the rest of setup.sh —
                  useful right after installing Firefox for the first time,
                  or once content-prefs.sqlite exists so the zoom setting
                  (which needs it, and doesn't exist on a brand-new profile)
                  can be applied on a second pass.
  -h, --help      Show this help.
EOF
}

main() {
  if [[ "$#" -gt 0 ]]; then
    case "$1" in
      --chrome-only)
        if [[ "$#" -ne 1 ]]; then
          log_error "--chrome-only does not accept additional arguments."
          exit 1
        fi
        configure_chrome
        return
        ;;
      --firefox-only)
        if [[ "$#" -ne 1 ]]; then
          log_error "--firefox-only does not accept additional arguments."
          usage >&2
          exit 1
        fi
        log "Refreshing Firefox profile configuration..."
        configure_firefox
        log_success "Firefox profile configuration refreshed."
        return
        ;;
      -h|--help)
        usage
        return
        ;;
      *)
        log_error "Unknown argument: $1"
        usage >&2
        exit 1
        ;;
    esac
  fi

  log "Applying Linux system tweaks..."

  install_firacode_nerd_font
  install_symbols_nerd_font
  disable_unused_daemons
  check_hyprland_session
  mask_desktop_user_units
  # The schedule's ExecStart must exist before its service/timer is started.
  configure_links
  enable_hyprmoncfg
  enable_night_light_schedule

  apply_gsettings_theme
  apply_gsettings_keyboard
  configure_firefox
  configure_chrome
  add_user_to_video_group

  restart_dunst

  log_success "Linux tweaks applied."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
