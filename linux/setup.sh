#!/usr/bin/env bash
set -euo pipefail

# Linux system tweaks and config glue that don't fit the standard symlink flow:
#   - Fonts (FiraCode Nerd Font, Symbols Nerd Font)
#   - System fixes that need sudo (unused ModemManager off, `video` group for
#     the backlight keys)
#   - Session/user-unit state: masking the hypridle/hyprpaper units this repo
#     autostarts from hyprland.lua instead, enabling hyprmoncfgd and the
#     night-light schedule timer
#   - gsettings that GTK/portal apps read (theme, fonts, cursor, keyboard),
#     kept in sync with hyprland.lua so GNOME and Hyprland feel the same
#   - Session scripts linked to absolute ~/.config/ paths (the shell uses them)
#   - Firefox profile glue (profile path is dynamic)
#   - Speaker amps: sof_sdw quirk override for the XPS 13's CS35L56 sidecar
#     amplifiers on kernels older than 7.2 (self-retiring)
#   - Speaker DRC: switches off SOF's default speaker compressor (stored in
#     the ALSA state file so udev's boot-time restore keeps it off)
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

enable_xps13_sidecar_amps() {
  # Dell XPS 13 DX13260 (DMI SKU 0E53) has two Cirrus CS35L56 "sidecar" speaker
  # amplifiers on SPI next to the cs42l43 codec. sof_sdw only wires them into
  # the sound card when the board quirk SOC_SDW_SIDECAR_AMPS (BIT(16) = 65536)
  # is set; upstream adds this SKU to the quirk table in commit efd80de2de9d,
  # which first ships in Linux 7.2-rc5. On older kernels the amps bind to their
  # driver but never join the card (no cs35l56 mixer controls, firmware
  # "patched=0") and the codec's tiny built-in amp drives the speakers alone —
  # thin and harsh. This is the same workaround Omarchy ships as its
  # dell-xps13-sidecar-amps package: a module option override. The module is
  # not in Fedora's initramfs, so /etc/modprobe.d is enough; it takes effect on
  # the next boot. Self-retiring: once the running kernel's module carries the
  # quirk entry itself, the drop-in is removed.
  local conf=/etc/modprobe.d/dell-xps13-sidecar-amps.conf
  local want='options snd_soc_sof_sdw quirk=65536'

  local sku
  sku="$(cat /sys/class/dmi/id/product_sku 2>/dev/null || true)"
  if [[ "${sku^^}" != "0E53" ]] || ! grep -qi "DX13260" /sys/class/dmi/id/product_name 2>/dev/null; then
    return
  fi

  local module
  module="$(modinfo -n snd_soc_sof_sdw 2>/dev/null || true)"
  if [[ -n "${module}" ]] && sof_sdw_module_has_dell_quirk "${module}"; then
    if [[ -f "${conf}" ]]; then
      sudo rm -f "${conf}"
      log_success "Kernel carries the XPS 13 sidecar amp quirk itself; removed ${conf}."
    else
      log_success "Kernel carries the XPS 13 sidecar amp quirk itself; no override needed."
    fi
    return
  fi

  if [[ -f "${conf}" ]] && grep -qxF "${want}" "${conf}"; then
    log_success "XPS 13 sidecar amp override already in place."
    return
  fi

  log "Enabling the XPS 13 CS35L56 sidecar speaker amplifiers (sof_sdw quirk override)..."
  sudo tee "${conf}" >/dev/null <<EOF
# Dell XPS 13 DX13260 (1028:0e53): enable the CS35L56 sidecar speaker amps.
# Managed by initd linux/setup.sh; removed automatically once the kernel's
# sof_sdw carries this quirk itself (Linux 7.2+, commit efd80de2de9d).
${want}
EOF
  log_warn "Reboot to enable the XPS 13 sidecar speaker amplifiers."
}

# True when the running kernel's snd_soc_sof_sdw already lists the Dell XPS
# WCL/PTL SKUs in its quirk table (the strings the upstream entry carries).
sof_sdw_module_has_dell_quirk() {
  local module="$1"
  case "${module}" in
    *.xz)  xz -dc "${module}" ;;
    *.zst) zstd -dc "${module}" ;;
    *)     cat "${module}" ;;
  esac 2>/dev/null | grep -aq 'Dell XPS WCL'
}

disable_speaker_drc() {
  # Intel's SOF speaker topology enables a dynamic-range compressor on the
  # speaker pipeline by default ("Post Mixer Speaker Playback DRC"). It is a
  # generic loudness leveller, not a tuning for this laptop, and it flattens
  # the mix — quiet instruments get pumped up and down with the vocal. The
  # Cirrus amp firmware does its own speaker protection, so switching it off
  # is safe; it is an ordinary ALSA mixer control, same as alsamixer would set.
  # Fedora's udev rule re-applies /var/lib/alsa/asound.state to the card on
  # every boot, so the live change has to be stored there too or it reverts.
  local control='Post Mixer Speaker Playback DRC switch'
  local state=/var/lib/alsa/asound.state

  if ! amixer -c 0 cget name="${control}" >/dev/null 2>&1; then
    return   # not this sound card / topology
  fi

  local live stored
  live="$(amixer -c 0 cget name="${control}" | grep -oE 'values=(on|off)' | cut -d= -f2)"
  stored="$(grep -A1 -F "name '${control}'" "${state}" 2>/dev/null | grep -oE 'value (true|false)' | cut -d' ' -f2)"

  if [[ "${live}" == "off" && "${stored}" == "false" ]]; then
    log_success "Speaker DRC already off (live and stored)."
    return
  fi

  [[ "${live}" == "off" ]] || amixer -c 0 cset name="${control}" off >/dev/null
  sudo alsactl store
  log_success "Speaker DRC switched off and stored in ${state}."
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
  systemctl --user daemon-reload
  systemctl --user enable --now hyprmoncfgd.service
  log_success "hyprmoncfg monitor profile service enabled."
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

# Firefox's profile root varies by install/version:
#   - legacy ~/.mozilla/firefox — used whenever it exists (takes priority)
#   - XDG ~/.config/mozilla/firefox — Firefox 143+ default when no legacy dir
# Match Firefox's own resolution order: legacy first, then XDG.
find_firefox_profile_root() {
  local candidate
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

# Resolves the active Firefox profile directory into FIREFOX_PROFILE_DIR
# (empty when there is none), creating a fresh profile non-interactively if
# Firefox is installed but has never run. Shared by link_firefox_profile and
# set_firefox_default_zoom; the lookup runs once per setup.sh invocation, so
# profiles.ini is parsed (and any profile created) a single time. Sets a
# global rather than printing because a `$(...)` caller would run in a
# subshell and lose the cache.
FIREFOX_PROFILE_DIR=""
FIREFOX_PROFILE_RESOLVED=0
resolve_firefox_profile_dir() {
  [[ "${FIREFOX_PROFILE_RESOLVED}" == "1" ]] && return
  FIREFOX_PROFILE_RESOLVED=1
  FIREFOX_PROFILE_DIR="$(find_firefox_profile_dir || true)"
}

find_firefox_profile_dir() {
  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 not available — skipping firefox profile detection."
    return 1
  fi

  local moz_dir
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
  resolve_firefox_profile_dir
  local ff_dir="${FIREFOX_PROFILE_DIR}"
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
  resolve_firefox_profile_dir
  local ff_dir="${FIREFOX_PROFILE_DIR}"
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
  enable_xps13_sidecar_amps
  disable_speaker_drc
  check_hyprland_session
  mask_desktop_user_units
  enable_hyprmoncfg
  enable_night_light_schedule
  link_ghostty_linux_conf

  apply_gsettings_theme
  apply_gsettings_keyboard
  disable_copyq_tray
  link_gtkrc_2
  link_icons_default
  link_session_scripts
  link_firefox_profile
  set_firefox_default_zoom
  add_user_to_video_group

  restart_dunst

  log_success "Linux tweaks applied."
}

main "$@"
