#!/usr/bin/env bash
set -euo pipefail

# Linux system tweaks and config glue that don't fit the standard symlink flow:
#   - Fonts (FiraCode Nerd Font, Symbols Nerd Font)
#   - System fixes that need sudo (unused ModemManager off, `video` group for
#     the backlight keys)
#   - Session/user-unit state: masking the hypridle/hyprpaper units this repo
#     autostarts from hyprland.lua instead, enabling hyprmoncfgd, seeding the
#     hyprmoncfg monitor stub
#   - gsettings that GTK/portal apps read (theme, fonts, cursor, keyboard),
#     kept in sync with hyprland.lua so GNOME and Hyprland feel the same
#   - Session scripts linked to absolute ~/.config/ paths (the shell uses them)
#   - Firefox profile glue (profile path is dynamic)
#   - Speaker EQ: enables PipeWire's filter-chain sink and makes it the default
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
# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/fs.sh"

# ── Fonts ─────────────────────────────────────────────────────────────────────
install_firacode_nerd_font() {
  local font_dir="${HOME}/.local/share/fonts/FiraCode"

  if ls "${font_dir}"/*.ttf >/dev/null 2>&1; then
    log_success "FiraCode Nerd Font already installed."
    return
  fi

  require_command curl "to download Nerd Fonts"
  require_command unzip "to extract Nerd Fonts"

  mkdir -p "${font_dir}"
  log "Downloading FiraCode Nerd Font..."
  curl -fL --progress-bar --max-time 300 \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" \
    -o /tmp/FiraCode-nerd.zip
  unzip -q -o /tmp/FiraCode-nerd.zip "*.ttf" -d "${font_dir}"
  rm -f /tmp/FiraCode-nerd.zip
  fc-cache -f "${font_dir}" >/dev/null
  log_success "FiraCode Nerd Font installed."
}

install_symbols_nerd_font() {
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
  log "Downloading Symbols Nerd Font..."
  curl -fL --progress-bar --max-time 300 \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip" \
    -o /tmp/SymbolsNerd.zip
  unzip -q -o /tmp/SymbolsNerd.zip "*.ttf" -d "${font_dir}"
  rm -f /tmp/SymbolsNerd.zip
  fc-cache -f "${font_dir}" >/dev/null
  log_success "Symbols Nerd Font installed."
}

# ── System fixes ──────────────────────────────────────────────────────────────
disable_modemmanager() {
  # No cellular modem on this hardware (mmcli -L finds none) — ModemManager is
  # a NetworkManager-optional plugin, so disabling it is safe and just trims
  # an idle background daemon.
  if [[ "$(systemctl is-enabled ModemManager.service 2>/dev/null)" == "disabled" ]]; then
    log_success "ModemManager already disabled."
    return
  fi
  sudo systemctl disable --now ModemManager.service >/dev/null 2>&1
  log_success "ModemManager disabled (no modem hardware present)."
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

  systemctl --user daemon-reload
}

enable_hyprmoncfg() {
  if ! command -v hyprmoncfgd >/dev/null 2>&1; then
    log_warn "hyprmoncfgd not found; skipping monitor profile service."
    return
  fi
  systemctl --user daemon-reload
  systemctl --user enable --now hyprmoncfgd.service
  log_success "hyprmoncfg monitor profile service enabled."
}

link_ghostty_linux_conf() {
  # Ghostty has no per-OS include (config-file does no variable expansion), so
  # the Linux-only file has to be placed next to the shared config by this
  # script rather than selected by name the way kitty's ${KITTY_OS}.conf is.
  # The shared config ends with `config-file = ?linux.conf`; the `?` makes it
  # optional, so on macOS — where nothing creates this link — it is a no-op.
  local target="${ROOT_DIR}/shared/configs/ghostty/.config/ghostty/linux.conf"
  local src="${CONFIGS_DIR}/ghostty/linux.conf"

  # The directory is tracked (config lives in it), but mkdir -p keeps this from
  # being the one step that fails on a partial or hand-made checkout.
  mkdir -p "$(dirname "${target}")"

  if [[ -L "${target}" ]] && [[ "$(readlink "${target}")" == "${src}" ]]; then
    log_success "Ghostty linux.conf already linked."
  else
    [[ -e "${target}" || -L "${target}" ]] && backup_path "${target}"
    ln -s "${src}" "${target}"
    log_success "Linked Ghostty linux.conf -> ${src}"
  fi
}

seed_hyprmoncfg_monitors() {
  local target="${HOME}/.config/hypr/hyprmoncfg-monitors.lua"

  if [[ -e "${target}" ]]; then
    log_success "hyprmoncfg monitor rules already present."
    return
  fi

  if [[ ! -d "${HOME}/.config/hypr" ]]; then
    log_warn "~/.config/hypr missing; skipping hyprmoncfg monitor stub."
    return
  fi

  # hyprland.lua ends with a bare dofile() of this path, and hyprmoncfg insists on
  # that exact unprotected form (it re-appends it whenever its rules fail to load).
  # The file itself is generated and gitignored, so it does not exist until the
  # first profile is saved — without a stub, dofile() aborts config parsing on a
  # fresh bootstrap. An empty stub is valid Lua and leaves the static fallback
  # rules in hyprland.lua in effect; hyprmoncfg overwrites it on first apply.
  cat > "${target}" <<'EOF'
-- Placeholder seeded by linux/setup.sh so hyprland.lua's dofile() has a target
-- before the first hyprmoncfg profile exists. hyprmoncfg overwrites this file
-- with the real monitor rules as soon as a profile is applied; until then the
-- static hl.monitor() fallbacks near the top of hyprland.lua are what apply.
EOF
  log_success "Seeded hyprmoncfg monitor stub (no profile saved yet)."
}

# ── Config glue (special-case paths) ─────────────────────────────────────────
link_gtkrc_2() {
  local target="${HOME}/.gtkrc-2.0"
  local src="${CONFIGS_DIR}/gtkrc-2.0"

  if [[ -L "${target}" ]] && [[ "$(readlink "${target}")" == "${src}" ]]; then
    log_success ".gtkrc-2.0 already linked."
  else
    [[ -e "${target}" || -L "${target}" ]] && backup_path "${target}"
    ln -s "${src}" "${target}"
    log_success "Linked ~/.gtkrc-2.0 -> ${src}"
  fi
}

link_icons_default() {
  local target_dir="${HOME}/.icons/default"
  local target="${target_dir}/index.theme"
  local src="${CONFIGS_DIR}/icons-default/index.theme"

  mkdir -p "${target_dir}"
  if [[ -L "${target}" ]] && [[ "$(readlink "${target}")" == "${src}" ]]; then
    log_success "icons default already linked."
  else
    [[ -e "${target}" || -L "${target}" ]] && backup_path "${target}"
    ln -s "${src}" "${target}"
    log_success "Linked default icon theme."
  fi
}

link_session_scripts() {
  # hyprland.lua/Quickshell invoke these by absolute ~/.config/ path, so they need
  # their own symlinks (they live in linux/scripts/, not under a MANAGED_LINKS dir).
  local name target src
  for name in night-light-toggle.sh \
              weather-popup.sh docker-menu.sh audio-ports.sh; do
    target="${HOME}/.config/${name}"
    src="${SCRIPTS_DIR}/${name}"
    chmod +x "${src}" 2>/dev/null || true
    if [[ -L "${target}" ]] && [[ "$(readlink "${target}")" == "${src}" ]]; then
      log_success "${name} already linked."
    else
      [[ -e "${target}" || -L "${target}" ]] && backup_path "${target}"
      ln -s "${src}" "${target}"
      log_success "Linked ~/.config/${name}"
    fi
  done
}

# Resolves the active Firefox profile directory, creating a fresh profile
# non-interactively if none exists yet. Prints the profile dir and returns 0,
# or prints nothing and returns 1. Shared by link_firefox_profile and
# set_firefox_default_zoom.
resolve_firefox_profile_dir() {
  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 not available — skipping firefox profile detection."
    return 1
  fi

  # Firefox's profile root varies by install/version:
  #   - legacy ~/.mozilla/firefox — used whenever it exists (takes priority)
  #   - XDG ~/.config/mozilla/firefox — Firefox 143+ default when no legacy dir
  # Match Firefox's own resolution order: legacy first, then XDG.
  local moz_dir=""
  local candidate
  find_firefox_profile_root() {
    for candidate in \
      "${HOME}/.mozilla/firefox" \
      "${XDG_CONFIG_HOME:-${HOME}/.config}/mozilla/firefox"
    do
      if [[ -f "${candidate}/profiles.ini" ]]; then
        printf '%s\n' "${candidate}"
        return 0
      fi
    done
    return 1
  }

  moz_dir="$(find_firefox_profile_root || true)"

  # A freshly installed Firefox has no profiles.ini until its first launch.
  # Create the profile non-interactively so this initial bootstrap can install
  # user.js and userChrome.css immediately rather than requiring a second run.
  if [[ -z "${moz_dir}" ]] && command -v firefox >/dev/null 2>&1; then
    log "Initializing the managed Firefox profile..."
    if firefox --headless --CreateProfile default-release >/dev/null 2>&1; then
      moz_dir="$(find_firefox_profile_root || true)"
    else
      log_warn "Firefox could not initialize a profile — retry on the next setup run."
    fi
  fi

  [[ -z "${moz_dir}" ]] && return 1

  # Firefox 67+ tracks the active profile per-install via an [InstallXXXX]
  # section whose Default= value is the profile path directly — this takes
  # priority over the legacy per-profile Default=1 flag, which Firefox stops
  # updating once an [Install...] section exists.
  local ff_profile
  ff_profile="$(python3 - "${moz_dir}/profiles.ini" <<'PYEOF'
import configparser, sys
p = configparser.ConfigParser()
p.read(sys.argv[1])
for s in p.sections():
    if s.startswith("Install"):
        path = p.get(s, "Default", fallback="")
        if path:
            print(path)
            sys.exit(0)
for s in p.sections():
    if p.get(s, "Default", fallback="0") == "1" and p.get(s, "Path", fallback=""):
        print(p.get(s, "Path"))
        sys.exit(0)
PYEOF
)"

  [[ -z "${ff_profile}" ]] && return 1

  if [[ "${ff_profile}" = /* ]]; then
    printf '%s\n' "${ff_profile}"
  else
    printf '%s\n' "${moz_dir}/${ff_profile}"
  fi
}

link_firefox_profile() {
  local ff_dir
  ff_dir="$(resolve_firefox_profile_dir || true)"
  if [[ -z "${ff_dir}" ]]; then
    log "No firefox profile present — skipping."
    return
  fi
  mkdir -p "${ff_dir}/chrome"

  local pair target src
  for pair in \
    "user.js:${ff_dir}/user.js" \
    "chrome/userChrome.css:${ff_dir}/chrome/userChrome.css" \
    "chrome/userContent.css:${ff_dir}/chrome/userContent.css"
  do
    target="${pair#*:}"
    src="${CONFIGS_DIR}/firefox/${pair%%:*}"
    [[ -f "${src}" ]] || continue
    if [[ -L "${target}" ]] && [[ "$(readlink "${target}")" == "${src}" ]]; then
      continue
    fi
    [[ -e "${target}" || -L "${target}" ]] && rm -f "${target}"
    ln -s "${src}" "${target}"
    log_success "Linked $(basename "${target}")"
  done
}

set_firefox_default_zoom() {
  # Firefox's Zoom UI reads per-site full-zoom levels from content-prefs.sqlite,
  # not from any user.js pref — this sets 133% as the default for any site
  # that doesn't already have its own saved zoom level.
  local ff_dir
  ff_dir="$(resolve_firefox_profile_dir || true)"
  [[ -z "${ff_dir}" ]] && return

  local content_prefs="${ff_dir}/content-prefs.sqlite"
  if pgrep -x firefox >/dev/null 2>&1; then
    log_warn "Firefox is running — leaving its default zoom unchanged. Close Firefox and re-run setup.sh to set 133%."
    return
  fi
  if [[ ! -f "${content_prefs}" ]]; then
    log_warn "Firefox content preferences are not initialized yet — open Firefox once, close it, then re-run setup.sh to set 133% zoom."
    return
  fi

  if python3 - "${content_prefs}" <<'PYEOF'
import sqlite3, sys, time

db = sqlite3.connect(sys.argv[1], timeout=2)
try:
    setting = "browser.content.full-zoom"
    row = db.execute("SELECT id FROM settings WHERE name = ? ORDER BY id LIMIT 1", (setting,)).fetchone()
    if row is None:
        cursor = db.execute("INSERT INTO settings (name) VALUES (?)", (setting,))
        setting_id = cursor.lastrowid
    else:
        setting_id = row[0]
    db.execute("DELETE FROM prefs WHERE groupID IS NULL AND settingID = ?", (setting_id,))
    db.execute(
        "INSERT INTO prefs (groupID, settingID, value, timestamp) VALUES (NULL, ?, ?, ?)",
        (setting_id, 1.33, int(time.time() * 1_000_000)),
    )
    db.commit()
finally:
    db.close()
PYEOF
  then
    log_success "Set Firefox default zoom to 133%."
  else
    # Firefox can keep the database locked even when its main process name
    # is not exactly "firefox". A cosmetic preference must not abort the
    # rest of the idempotent system setup.
    log_warn "Firefox preferences database is busy — leaving default zoom unchanged. Close Firefox and re-run setup.sh to set 133%."
  fi
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

disable_copyq_tray() {
  # hyprland.lua starts CopyQ as a background clipboard-history server
  # (mod+c toggles its window) — it is neither a tray app nor a boot window.
  # `copyq config` writes to ~/.config/copyq/copyq.conf directly, so this is
  # idempotent and safe to re-run.
  if ! command -v copyq >/dev/null 2>&1; then
    log_warn "copyq not found; skipping tray icon setting."
    return
  fi
  if [[ "$(copyq config disable_tray 2>/dev/null)" == "true" ]] &&
     [[ "$(copyq config hide_main_window 2>/dev/null)" == "true" ]]; then
    log_success "CopyQ is already trayless and hidden at startup."
    return
  fi
  copyq config disable_tray true >/dev/null 2>&1
  copyq config hide_main_window true >/dev/null 2>&1
  log_success "CopyQ configured without a tray or startup window."
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

enable_audio_eq() {
  # Corrects the XPS 13 cs42l43 speakers' thin/tinny stock output — see
  # linux/configs/pipewire/filter-chain.conf.d/sink-eq6.conf for the curve
  # itself. filter-chain.service (a stock PipeWire unit) loads that config
  # and creates the "Equalizer Sink" node; this just wires it up as the
  # default output with makeup gain, since removing that much energy from
  # the upper-mid/treble drops perceived loudness.
  if ! command -v pactl >/dev/null 2>&1; then
    log_warn "pactl not found; skipping audio EQ setup."
    return
  fi

  systemctl --user enable --now filter-chain.service >/dev/null 2>&1

  local attempt
  for attempt in $(seq 1 10); do
    if pactl list short sinks 2>/dev/null | grep -q "effect_input.eq6"; then
      break
    fi
    sleep 0.5
  done

  if ! pactl list short sinks 2>/dev/null | grep -q "effect_input.eq6"; then
    log_warn "effect_input.eq6 sink never appeared; skipping default-sink/volume setup."
    return
  fi

  pactl set-default-sink effect_input.eq6
  pactl set-sink-volume effect_input.eq6 105%
  log_success "Audio EQ enabled (Equalizer Sink set as default, 105% makeup gain)."
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
Usage: ${0##*/} [--firefox-only]

Apply Linux system tweaks and managed configuration.

Options:
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
      --firefox-only)
        if [[ "$#" -ne 1 ]]; then
          log_error "--firefox-only does not accept additional arguments."
          usage >&2
          exit 1
        fi
        log "Refreshing Firefox profile configuration..."
        link_firefox_profile
        set_firefox_default_zoom
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
  disable_modemmanager
  check_hyprland_session
  mask_desktop_user_units
  enable_hyprmoncfg
  link_ghostty_linux_conf
  seed_hyprmoncfg_monitors

  apply_gsettings_theme
  apply_gsettings_keyboard
  disable_copyq_tray
  link_gtkrc_2
  link_icons_default
  link_session_scripts
  link_firefox_profile
  set_firefox_default_zoom
  add_user_to_video_group
  enable_audio_eq

  restart_dunst

  log_success "Linux tweaks applied."
}

main "$@"
