#!/usr/bin/env bash
set -euo pipefail

# Linux system tweaks and config glue that don't fit the standard symlink flow:
#   - Fonts (FiraCode Nerd Font)
#   - System fixes that need sudo (WiFi, NetworkManager, swappiness)
#   - Power-profile auto-switch (udev + polkit; works under any session)
#   - Session scripts linked to absolute ~/.config/ paths (waybar/hyprland use them)
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

# ── System fixes ──────────────────────────────────────────────────────────────
apply_intel_wifi_d3cold_fix() {
  # Intel BE200 (vendor 8086, device 272b) wedges firmware when entering PCIe D3cold.
  # Keep the device in D3hot across suspend.
  local wifi_udev=/etc/udev/rules.d/10-intel-wifi-d3cold.rules
  local wifi_udev_rule='ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x272b", ATTR{d3cold_allowed}="0"'

  if [[ -f "${wifi_udev}" ]] && grep -qF "${wifi_udev_rule}" "${wifi_udev}"; then
    log_success "Intel WiFi d3cold udev rule already installed."
  else
    echo "${wifi_udev_rule}" | sudo tee "${wifi_udev}" >/dev/null
    sudo udevadm control --reload
    log_success "Intel WiFi d3cold udev rule installed."
  fi

  local wifi_pci
  wifi_pci="$(lspci -D 2>/dev/null | awk '/Network controller.*Intel/{print $1; exit}' || true)"
  if [[ -n "${wifi_pci}" ]] && [[ -e "/sys/bus/pci/devices/${wifi_pci}" ]]; then
    sudo udevadm trigger --action=add "/sys/bus/pci/devices/${wifi_pci}"
    log "d3cold_allowed=0 applied to ${wifi_pci}"
  fi

  # Old hooks for the same problem — clean up if they exist.
  local _old
  for _old in /etc/systemd/system-sleep/wifi-resume.sh /usr/lib/systemd/system-sleep/wifi-resume.sh /etc/modprobe.d/iwlmvm.conf; do
    if [[ -f "${_old}" ]]; then
      sudo rm -f "${_old}"
      log "Removed stale ${_old}"
    fi
  done
}

apply_wifi_regdomain() {
  # Without a regulatory domain the kernel sits in the "world" domain
  # (country 00): the whole 6 GHz band is disabled and TX power is capped,
  # so the BE200 can never use WiFi 6E/7's fastest band. Persist via the
  # cfg80211 module option (applies at boot; legacy /etc/default/crda is dead).
  local regdomain="AU"
  local conf=/etc/modprobe.d/cfg80211.conf
  local line="options cfg80211 ieee80211_regdom=${regdomain}"

  if [[ -f "${conf}" ]] && grep -qxF "${line}" "${conf}"; then
    log_success "WiFi regulatory domain already set (${regdomain})."
    return
  fi
  echo "${line}" | sudo tee "${conf}" >/dev/null
  # Best-effort immediate apply; fully in effect after reboot/module reload.
  command -v iw >/dev/null 2>&1 && sudo iw reg set "${regdomain}" 2>/dev/null || true
  log_success "WiFi regulatory domain set to ${regdomain} (6 GHz enabled after reboot)."
}

apply_wifi_reconnect_speedup() {
  # Disable NM's WiFi power save so the card doesn't doze between scans.
  local nm_powersave=/etc/NetworkManager/conf.d/wifi-powersave.conf
  if [[ -f "${nm_powersave}" ]] && grep -q 'wifi.powersave = 2' "${nm_powersave}"; then
    log_success "WiFi power save already disabled."
  else
    sudo mkdir -p /etc/NetworkManager/conf.d
    printf '[connection]\nwifi.powersave = 2\n' | sudo tee "${nm_powersave}" >/dev/null
    log_success "WiFi power save disabled."
  fi

  local reconnect_hook=/etc/systemd/system-sleep/wifi-reconnect.sh
  sudo mkdir -p /etc/systemd/system-sleep
  if [[ -f "${reconnect_hook}" ]] && diff -q "${SCRIPTS_DIR}/wifi-reconnect.sh" "${reconnect_hook}" >/dev/null 2>&1; then
    log_success "WiFi reconnect hook already installed."
  else
    sudo cp "${SCRIPTS_DIR}/wifi-reconnect.sh" "${reconnect_hook}"
    sudo chmod +x "${reconnect_hook}"
    log_success "WiFi reconnect hook installed."
  fi
}

apply_chrome_apt_arch() {
  local chrome_sources=/etc/apt/sources.list.d/google-chrome.sources
  if [[ ! -f "${chrome_sources}" ]]; then
    log "google-chrome.sources not present — skipping."
    return
  fi
  if grep -q 'Architectures:' "${chrome_sources}"; then
    log_success "Chrome apt arch already pinned."
    return
  fi
  sudo sed -i 's/^Types: deb$/Types: deb\nArchitectures: amd64/' "${chrome_sources}"
  log_success "Chrome apt arch pinned to amd64."
}

enable_power_profiles_daemon() {
  local cpu_svc=/etc/systemd/system/cpu-performance.service
  if [[ -f "${cpu_svc}" ]]; then
    sudo systemctl disable --now cpu-performance.service 2>/dev/null || true
    sudo rm -f "${cpu_svc}"
    log "Removed static performance governor service."
  fi

  if systemctl is-active --quiet power-profiles-daemon \
      && systemctl is-enabled --quiet power-profiles-daemon; then
    log_success "power-profiles-daemon already running and enabled."
    return
  fi
  sudo systemctl unmask power-profiles-daemon 2>/dev/null || true
  if sudo systemctl enable --now power-profiles-daemon; then
    log_success "power-profiles-daemon enabled."
  else
    log_warn "Could not enable power-profiles-daemon — may conflict with another power manager."
  fi
}

install_power_profile_autoswitch() {
  # Auto-switch the PPD profile on AC vs battery via a udev-triggered script
  # (Hyprland has no GNOME/KDE-style logic to do this). The udev hook runs as
  # root with no active session, so a polkit rule is needed or the switch is denied.
  local switch_bin=/usr/local/bin/power-profile-switch.sh
  local udev_rule=/etc/udev/rules.d/99-power-profile.rules
  local polkit_rule=/etc/polkit-1/rules.d/49-power-profiles.rules
  local udev_changed=0

  if [[ -f "${switch_bin}" ]] && diff -q "${SCRIPTS_DIR}/power-profile-switch.sh" "${switch_bin}" >/dev/null 2>&1; then
    log_success "Power-profile switcher already installed."
  else
    sudo cp "${SCRIPTS_DIR}/power-profile-switch.sh" "${switch_bin}"
    sudo chmod +x "${switch_bin}"
    log_success "Power-profile switcher installed."
  fi

  if [[ -f "${udev_rule}" ]] && diff -q "${SCRIPTS_DIR}/99-power-profile.rules" "${udev_rule}" >/dev/null 2>&1; then
    log_success "Power-profile udev rule already installed."
  else
    sudo cp "${SCRIPTS_DIR}/99-power-profile.rules" "${udev_rule}"
    udev_changed=1
    log_success "Power-profile udev rule installed."
  fi

  sudo mkdir -p /etc/polkit-1/rules.d
  if [[ -f "${polkit_rule}" ]] && diff -q "${SCRIPTS_DIR}/49-power-profiles.rules" "${polkit_rule}" >/dev/null 2>&1; then
    log_success "Power-profile polkit rule already installed."
  else
    sudo cp "${SCRIPTS_DIR}/49-power-profiles.rules" "${polkit_rule}"
    log_success "Power-profile polkit rule installed."
  fi

  if [[ "${udev_changed}" -eq 1 ]]; then
    sudo udevadm control --reload-rules
    log "Reloaded udev rules."
  fi
  # Sync to the current AC/battery state right away.
  "${switch_bin}" 2>/dev/null || true
}

apply_swappiness() {
  local sysctl_conf=/etc/sysctl.d/99-performance.conf
  if [[ -f "${sysctl_conf}" ]] && grep -q 'swappiness=10' "${sysctl_conf}"; then
    log_success "swappiness already set to 10."
    return
  fi
  echo 'vm.swappiness=10' | sudo tee "${sysctl_conf}" >/dev/null
  sudo sysctl -p "${sysctl_conf}" >/dev/null
  log_success "swappiness set to 10."
}

# ── Hyprland session ──────────────────────────────────────────────────────────
check_hyprland_session() {
  # The apt hyprland package ships the GDM session entry; verify it's there so
  # the login screen actually offers Hyprland next to GNOME.
  if [[ -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    log_success "Hyprland session available at the login screen."
  else
    log_warn "No /usr/share/wayland-sessions/hyprland.desktop — is the hyprland package installed?"
  fi
}

mask_desktop_user_units() {
  # Ubuntu's waybar/hypridle/hyprpaper packages ship systemd user units enabled
  # at graphical-session.target, so they also launch inside GNOME sessions
  # (where waybar can't work — no layer-shell — and hyprpaper segfaults) and
  # race the exec-once entries in hyprland.conf under Hyprland. This repo owns
  # autostart via hyprland.conf, so mask the units at the user level.
  local unit
  for unit in waybar.service hypridle.service hyprpaper.service; do
    if [[ "$(systemctl --user is-enabled "${unit}" 2>/dev/null)" == "masked" ]]; then
      log_success "${unit} already masked."
    else
      systemctl --user mask "${unit}" >/dev/null 2>&1
      log_success "Masked ${unit} (autostarted via hyprland.conf exec-once instead)."
    fi
  done
}

# ── GTK theme (adw-gtk3) ─────────────────────────────────────────────────────
ADW_GTK3_VERSION="v6.5"

install_adw_gtk3_theme() {
  # Modern libadwaita-style dark theme for GTK3 apps, referenced by
  # gtk-3.0/settings.ini and gtkrc-2.0. Not packaged for Ubuntu, so pull the
  # prebuilt release tarball (no sudo needed).
  local themes_dir="${HOME}/.local/share/themes"
  local stamp="${themes_dir}/adw-gtk3-dark/.initd-version"

  if [[ -f "${stamp}" ]] && [[ "$(cat "${stamp}")" == "${ADW_GTK3_VERSION}" ]]; then
    log_success "adw-gtk3 ${ADW_GTK3_VERSION} already installed."
    return
  fi

  require_command curl "to download the adw-gtk3 theme"
  mkdir -p "${themes_dir}"
  log "Downloading adw-gtk3 ${ADW_GTK3_VERSION}..."
  curl -fL --max-time 120 \
    "https://github.com/lassekongo83/adw-gtk3/releases/download/${ADW_GTK3_VERSION}/adw-gtk3${ADW_GTK3_VERSION}.tar.xz" \
    | tar -xJ -C "${themes_dir}"
  echo "${ADW_GTK3_VERSION}" > "${stamp}"
  log_success "adw-gtk3 ${ADW_GTK3_VERSION} installed to ~/.local/share/themes."
}

# ── Config glue (special-case paths) ─────────────────────────────────────────
link_gtkrc_2() {
  local target="${HOME}/.gtkrc-2.0"
  local src="${CONFIGS_DIR}/gtkrc-2.0"

  if [[ -L "${target}" ]] && [[ "$(readlink "${target}")" == "${src}" ]]; then
    log_success ".gtkrc-2.0 already linked."
  else
    [[ -e "${target}" || -L "${target}" ]] && rm -f "${target}"
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
    [[ -e "${target}" || -L "${target}" ]] && rm -f "${target}"
    ln -s "${src}" "${target}"
    log_success "Linked default icon theme."
  fi
}

link_session_scripts() {
  # hyprland.conf/waybar invoke these by absolute ~/.config/ path, so they need
  # their own symlinks (they live in linux/scripts/, not under a MANAGED_LINKS dir).
  local name target src
  for name in power-profile-cycle.sh power-profile-status.sh \
              night-light-toggle.sh clamshell.sh \
              weather-popup.sh docker-menu.sh; do
    target="${HOME}/.config/${name}"
    src="${SCRIPTS_DIR}/${name}"
    chmod +x "${src}" 2>/dev/null || true
    if [[ -L "${target}" ]] && [[ "$(readlink "${target}")" == "${src}" ]]; then
      log_success "${name} already linked."
    else
      [[ -e "${target}" || -L "${target}" ]] && rm -f "${target}"
      ln -s "${src}" "${target}"
      log_success "Linked ~/.config/${name}"
    fi
  done
}

link_firefox_profile() {
  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 not available — skipping firefox profile linking."
    return
  fi

  # Firefox's profile root varies by install/version:
  #   - legacy ~/.mozilla/firefox — used whenever it exists (takes priority)
  #   - XDG ~/.config/mozilla/firefox — Firefox 143+ default when no legacy dir
  #   - ~/snap/firefox/common/.mozilla/firefox — the snap sandbox (fallback;
  #     bootstrap removes snap, but a pre-bootstrap profile may live there)
  # Match Firefox's own resolution order: legacy first, then XDG, then snap.
  local moz_dir=""
  local candidate
  for candidate in \
    "${HOME}/.mozilla/firefox" \
    "${XDG_CONFIG_HOME:-${HOME}/.config}/mozilla/firefox" \
    "${HOME}/snap/firefox/common/.mozilla/firefox"
  do
    if [[ -f "${candidate}/profiles.ini" ]]; then
      moz_dir="${candidate}"
      break
    fi
  done

  if [[ -z "${moz_dir}" ]]; then
    log "No firefox profile present — skipping."
    return
  fi

  local ff_profile
  ff_profile="$(python3 - "${moz_dir}/profiles.ini" <<'PYEOF'
import configparser, sys
p = configparser.ConfigParser()
p.read(sys.argv[1])
# Firefox 67+ tracks the active profile per-install via an [InstallXXXX]
# section whose Default= value is the profile path directly — this takes
# priority over the legacy per-profile Default=1 flag, which Firefox stops
# updating once an [Install...] section exists.
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

  if [[ -z "${ff_profile}" ]]; then
    log_warn "Could not detect Firefox default profile — skipping."
    return
  fi

  local ff_dir="${moz_dir}/${ff_profile}"
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

  # Firefox stores the global default zoom in content-prefs.sqlite rather than
  # prefs.js, so user.js cannot express it. Only touch the database while
  # Firefox is closed; the next setup run will apply it if it is currently open.
  local content_prefs="${ff_dir}/content-prefs.sqlite"
  if pgrep -x firefox >/dev/null 2>&1; then
    log_warn "Firefox is running — leaving its default zoom unchanged. Close Firefox and re-run setup.sh to set 125%."
  elif [[ -f "${content_prefs}" ]]; then
    python3 - "${content_prefs}" <<'PYEOF'
import sqlite3, sys, time

db = sqlite3.connect(sys.argv[1])
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
        (setting_id, 1.25, int(time.time() * 1_000_000)),
    )
    db.commit()
finally:
    db.close()
PYEOF
    log_success "Set Firefox default zoom to 125%."
  else
    log_warn "Firefox content preferences are not initialized yet — open Firefox once, close it, then re-run setup.sh to set 125% zoom."
  fi
}

apply_gsettings_theme() {
  # GTK3 apps read gtk-3.0/settings.ini, but GTK4/libadwaita apps on Wayland
  # get their theme through xdg-desktop-portal, which reads gsettings/dconf.
  # Keep both in sync or modern apps silently fall back to Ubuntu's Yaru.
  if ! command -v gsettings >/dev/null 2>&1; then
    log_warn "gsettings not available — skipping theme sync."
    return
  fi
  gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
  gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
  gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
  gsettings set org.gnome.desktop.interface cursor-theme "DMZ-White"
  gsettings set org.gnome.desktop.interface cursor-size 24
  gsettings set org.gnome.desktop.interface font-name "Ubuntu Sans 11"
  gsettings set org.gnome.desktop.interface document-font-name "Ubuntu Sans 12"
  gsettings set org.gnome.desktop.interface monospace-font-name "FiraCode Nerd Font Mono 11"
  log_success "gsettings theme and fonts synced (Ubuntu Sans / FiraCode Nerd Font Mono)."
}

apply_gsettings_keyboard() {
  # Mirror hyprland.conf input settings in GNOME so both sessions feel the
  # same: caps lock as ctrl (kb_options = ctrl:nocaps) and key repeat
  # (repeat_delay = 200, repeat_rate = 35/s → interval 1000/35 ≈ 29ms).
  if ! command -v gsettings >/dev/null 2>&1; then
    log_warn "gsettings not available — skipping keyboard sync."
    return
  fi
  gsettings set org.gnome.desktop.input-sources xkb-options "['ctrl:nocaps']"
  gsettings set org.gnome.desktop.peripherals.keyboard delay 200
  gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 29
  log_success "gsettings keyboard synced (ctrl:nocaps, delay 200, interval 29ms)."
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

install_firefox_policies() {
  # System-wide Firefox enterprise policies: force-install the standard
  # extensions from Mozilla Add-ons. Read from /etc/firefox/policies on Linux;
  # survives Firefox package upgrades (unlike the distribution/ directory).
  local policies_dir="/etc/firefox/policies"
  local policies_file="${policies_dir}/policies.json"

  if [[ -f "${policies_file}" ]] && grep -q "uBlock0@raymondhill.net" "${policies_file}"; then
    log_success "Firefox policies already installed."
    return
  fi

  log "Installing Firefox policies (uBlock Origin, 1Password)..."
  sudo mkdir -p "${policies_dir}"
  sudo tee "${policies_file}" > /dev/null << 'EOF'
{
  "policies": {
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      },
      "{d634138d-c276-4fc8-924b-40a0ea21d284}": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi"
      }
    }
  }
}
EOF
  log_success "Firefox policies installed."
}

configure_copyq() {
  # CopyQ runs tray-less ($mod+c toggles it — see hyprland.conf); the setting
  # lives in CopyQ's own config and needs its server up to write. Skip quietly
  # when no session/server is available (first bootstrap from a TTY).
  command -v copyq >/dev/null 2>&1 || return 0
  if copyq config disable_tray true >/dev/null 2>&1; then
    log_success "CopyQ tray icon disabled."
  else
    log_warn "CopyQ server not reachable — tray setting will apply on next setup run."
  fi
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

main() {
  log "Applying Linux system tweaks..."

  install_firacode_nerd_font
  apply_intel_wifi_d3cold_fix
  apply_wifi_regdomain
  apply_wifi_reconnect_speedup
  apply_chrome_apt_arch
  enable_power_profiles_daemon
  install_power_profile_autoswitch
  apply_swappiness
  check_hyprland_session
  mask_desktop_user_units

  install_adw_gtk3_theme
  apply_gsettings_theme
  apply_gsettings_keyboard
  link_gtkrc_2
  link_icons_default
  link_session_scripts
  link_firefox_profile
  install_firefox_policies
  add_user_to_video_group
  configure_copyq

  restart_dunst

  log_success "Linux tweaks applied."
}

main "$@"
