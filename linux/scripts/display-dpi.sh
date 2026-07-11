#!/usr/bin/env bash
# Per-profile Xft DPI. X11 has a single global Xft.dpi, so the HiDPI laptop
# panel (2880x1800 @ 13") and the 4K external (32") can't get different values
# at the same time — instead the value follows the active autorandr profile.
#
# Applied two ways:
#   - xrdb merge            → apps launched from now on
#   - xsettingsd Xft/DPI    → GTK apps already running rescale live
#
# xsettingsd's config format has no include mechanism, so it runs off a
# generated file: the managed repo config plus the Xft/DPI line.
#
# Usage: display-dpi.sh [profile]   (defaults to the current autorandr profile)

profile="${1:-$(autorandr --current 2>/dev/null | head -n1)}"

# Virtual/unknown profile (fresh machine before `laptop` is saved, or the
# clone-largest fallback): if the laptop panel is the only active output,
# treat it as the laptop profile so first login gets the right scale.
if [[ -z "${profile}" || "${profile}" == "clone-largest" ]]; then
  monitors="$(xrandr --listmonitors 2>/dev/null | awk 'NR > 1 {print $NF}')"
  if [[ "${monitors}" == eDP* && "${monitors}" != *$'\n'* ]]; then
    profile=laptop
  fi
fi

case "${profile}" in
  laptop|default) dpi=144 ;;   # dense 13" panel needs the larger scale
  *)              dpi=108 ;;   # docked/external: 32" 4K, compact-UI preference
esac

# Cursor scales with the DPI (48px reference at 144). GTK apps resize it live
# via xsettingsd; the Gtk/CursorThemeSize in the repo config is the fallback
# that gets replaced here.
cursor=$(( 48 * dpi / 144 ))

printf 'Xft.dpi: %s\nXcursor.size: %s\n' "${dpi}" "${cursor}" | xrdb -merge

conf="${XDG_CACHE_HOME:-${HOME}/.cache}/xsettingsd.conf"
mkdir -p "$(dirname "${conf}")"
{
  grep -v '^Gtk/CursorThemeSize' "${HOME}/.config/xsettingsd/xsettingsd.conf"
  printf 'Xft/DPI %s\n' "$((dpi * 1024))"
  printf 'Gtk/CursorThemeSize %s\n' "${cursor}"
} > "${conf}"

# If xsettingsd is already running off the generated config, a HUP reloads it
# in place (no theme flash); otherwise (re)start it on the generated config.
if pgrep -f "xsettingsd -c ${conf}" >/dev/null 2>&1; then
  pkill -HUP -f "xsettingsd -c ${conf}"
else
  pkill -x xsettingsd 2>/dev/null
  while pgrep -x xsettingsd >/dev/null 2>&1; do sleep 0.1; done
  xsettingsd -c "${conf}" >/dev/null 2>&1 &
  disown
fi
