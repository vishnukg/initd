#!/usr/bin/env bash
set -euo pipefail

# Linux system tweaks and config glue that don't fit the standard symlink flow:
#   - Fonts (FiraCode Nerd Font)
#   - System fixes that need sudo (xorg, WiFi, NetworkManager, swappiness)
#   - Picom resume hook (lives under /etc/systemd/system-sleep/)
#   - Polybar hardware-specific patching (interface / battery / backlight names)
#   - Firefox profile glue (profile path is dynamic)
#   - .Xresources (lives at $HOME, not under .config)
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

NEEDS_REBOOT=0

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
  curl -L --progress-bar \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" \
    -o /tmp/FiraCode-nerd.zip
  unzip -q -o /tmp/FiraCode-nerd.zip "*.ttf" -d "${font_dir}"
  rm -f /tmp/FiraCode-nerd.zip
  fc-cache -f "${font_dir}" >/dev/null
  log_success "FiraCode Nerd Font installed."
}

# ── System fixes ──────────────────────────────────────────────────────────────
apply_screen_tearing_fix() {
  # /etc/X11/xorg.conf.d/ survives package upgrades; /usr/share/X11/xorg.conf.d/ does not.
  local xorg_conf=/etc/X11/xorg.conf.d/20-intel.conf

  sudo mkdir -p /etc/X11/xorg.conf.d
  if [[ -f "${xorg_conf}" ]] && grep -q 'TearFree' "${xorg_conf}"; then
    log_success "Screen tearing fix already applied."
  else
    sudo tee "${xorg_conf}" >/dev/null <<'EOF'
Section "Device"
  Identifier "Intel Graphics"
  Driver "modesetting"
  Option "TearFree" "true"
  Option "TripleBuffer" "true"
  Option "DRI" "iris"
EndSection
EOF
    log_success "Screen tearing fix written — reboot required."
    NEEDS_REBOOT=1
  fi

  if [[ -f /usr/share/X11/xorg.conf.d/20-intel.conf ]]; then
    sudo rm -f /usr/share/X11/xorg.conf.d/20-intel.conf
    log "Removed old /usr/share/X11/xorg.conf.d/20-intel.conf"
  fi
}

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

  if systemctl is-active --quiet power-profiles-daemon; then
    log_success "power-profiles-daemon already running."
    return
  fi
  sudo systemctl unmask power-profiles-daemon 2>/dev/null || true
  if sudo systemctl enable --now power-profiles-daemon; then
    log_success "power-profiles-daemon enabled."
  else
    log_warn "Could not enable power-profiles-daemon — may conflict with another power manager."
  fi
}

install_picom_resume_hook() {
  local picom_hook=/etc/systemd/system-sleep/picom-resume.sh
  sudo mkdir -p /etc/systemd/system-sleep
  if [[ -f "${picom_hook}" ]] && diff -q "${SCRIPTS_DIR}/picom-resume.sh" "${picom_hook}" >/dev/null 2>&1; then
    log_success "picom resume hook already installed."
  else
    sudo cp "${SCRIPTS_DIR}/picom-resume.sh" "${picom_hook}"
    sudo chmod +x "${picom_hook}"
    log_success "picom resume hook installed."
  fi

  if [[ -f /usr/lib/systemd/system-sleep/picom-resume.sh ]]; then
    sudo rm -f /usr/lib/systemd/system-sleep/picom-resume.sh
    log "Removed old /usr/lib/systemd/system-sleep/picom-resume.sh"
  fi
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

# ── Config glue (special-case paths) ─────────────────────────────────────────
link_xresources() {
  # ~/.Xresources lives at $HOME, not under ~/.config, so it's outside the
  # standard managed-links flow.
  local target="${HOME}/.Xresources"
  local src="${CONFIGS_DIR}/Xresources"

  if [[ -L "${target}" ]] && [[ "$(readlink "${target}")" == "${src}" ]]; then
    log_success ".Xresources already linked."
  else
    [[ -e "${target}" || -L "${target}" ]] && rm -f "${target}"
    ln -s "${src}" "${target}"
    log_success "Linked ~/.Xresources -> ${src}"
  fi
  xrdb "${target}" 2>/dev/null || true
}

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

patch_polybar_hardware() {
  # Auto-detect hardware names so polybar shows real values. Patches the source
  # file under linux/configs/, which is symlinked from ~/.config/polybar.
  local file="${CONFIGS_DIR}/polybar/config.ini"
  local wlan_iface battery backlight

  wlan_iface="$(ip -o link show 2>/dev/null | awk '$2 ~ /^w/ {gsub(/:/, "", $2); print $2; exit}' || true)"
  wlan_iface="${wlan_iface:-wlan0}"
  battery="$(ls /sys/class/power_supply/ 2>/dev/null | grep -i bat | head -1 || true)"
  battery="${battery:-BAT0}"
  backlight="$(ls /sys/class/backlight/ 2>/dev/null | head -1 || true)"
  backlight="${backlight:-intel_backlight}"

  _patch_kv() {
    local key="$1" val="$2"
    if grep -q "^${key}[[:space:]]*=[[:space:]]*${val}[[:space:]]*$" "${file}"; then
      log "polybar ${key} already = ${val}"
    else
      sed -i "s|^${key}[[:space:]]*=.*|${key} = ${val}|" "${file}"
      log_success "polybar ${key} -> ${val}"
    fi
  }
  _patch_kv "interface" "${wlan_iface}"
  _patch_kv "battery"   "${battery}"
  _patch_kv "card"      "${backlight}"

  chmod +x "${CONFIGS_DIR}/polybar/launch.sh" "${CONFIGS_DIR}/polybar/workspaces.sh"
}

link_firefox_profile() {
  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 not available — skipping firefox profile linking."
    return
  fi
  if [[ ! -f "${HOME}/.mozilla/firefox/profiles.ini" ]]; then
    log "No firefox profile present — skipping."
    return
  fi

  local ff_profile
  ff_profile="$(python3 - <<'PYEOF'
import configparser, os, sys
p = configparser.ConfigParser()
p.read(os.path.expanduser("~/.mozilla/firefox/profiles.ini"))
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

  local ff_dir="${HOME}/.mozilla/firefox/${ff_profile}"
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

# ── Service restarts (apply config changes without a reboot) ─────────────────
restart_dunst() {
  if pgrep -x dunst >/dev/null 2>&1; then
    pkill -x dunst; sleep 0.1
    dunst &
    log "dunst restarted."
  fi
}

restart_xsettingsd() {
  if pgrep -x xsettingsd >/dev/null 2>&1; then
    pkill -x xsettingsd; sleep 0.1
    xsettingsd &
    log "xsettingsd restarted."
  fi
}

main() {
  log "Applying Linux system tweaks..."

  install_firacode_nerd_font
  apply_screen_tearing_fix
  apply_intel_wifi_d3cold_fix
  apply_wifi_reconnect_speedup
  apply_chrome_apt_arch
  enable_power_profiles_daemon
  install_picom_resume_hook
  apply_swappiness

  link_xresources
  link_gtkrc_2
  link_icons_default
  patch_polybar_hardware
  link_firefox_profile

  restart_dunst
  restart_xsettingsd

  if [[ "${NEEDS_REBOOT}" -eq 1 ]]; then
    log_warn "Reboot required for screen tearing fix to take effect."
  fi

  log_success "Linux tweaks applied."
}

main "$@"
