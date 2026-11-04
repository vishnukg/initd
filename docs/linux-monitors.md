# Linux monitor handling (Hyprland)

`hyprmoncfg` owns monitor layout, named profiles, hotplug handling, and
closed-lid behavior. It is a terminal UI that applies changes safely and
reverts them unless confirmed.

The static rules at the top of `linux/configs/hypr/hyprland.lua` are only a
fallback before the first profile exists: the laptop panel and unknown external
monitors use their preferred modes at 1.33333x scale.

## Create profiles

Start a Hyprland session, then launch:

```bash
hyprmoncfg
```

Drag displays on the canvas; edit mode, scale, rotation, mirroring, and
workspace placement in the side panel. Press `s`, name the layout (for example
`desk` or `projector`), then press Enter. The daemon auto-selects the best
profile whenever monitors change or the laptop lid closes.

Useful commands:

```bash
hyprctl monitors              # inspect connected outputs
hyprmoncfg                    # open the layout editor
hyprmoncfg apply desk         # apply a saved profile
systemctl --user status hyprmoncfgd
```

## Switching profiles from the bar

The Quickshell bar's monitor icon opens a profile switcher: a read-only list of
the connected displays with their current mode and scale, over the saved
profiles with the active one checked. Clicking a profile runs
`hyprmoncfg apply <name> --confirm-timeout 0`.

The switcher only *picks* between profiles that already exist. Creating and
arranging one is still a `hyprmoncfg` TUI job — the CLI's `save` only snapshots
whatever layout is applied right now, and there is no command to set an
individual monitor's mode.

`--confirm-timeout 0` is not optional. Interactively, `apply` asks
`Keep this configuration? [y/N] (auto-revert in 10s)`; with no terminal on the
other end it reads EOF, reverts the profile and exits 1, so a bar click would
appear to do nothing. Disabling the prompt gives up the auto-revert safety net,
which is acceptable only because every profile offered was saved from a layout
that already worked.

An apply can still be refused — hyprmoncfg validates before it commits, and a
profile saved against a different external monitor usually fails with
`layout overlaps: DP-1 intersects eDP-1`. The popup has already closed by then,
so the first line of stderr is raised as a notification rather than swallowed.

## Configuration ownership

The managed `~/.config/hyprmoncfg/` directory stores the portable profile
JSON, plus generated per-profile Lua and hyprlang fallbacks. Commit intentional
profile changes there.

Profiles that share the same connected displays cannot be auto-selected from
hardware identity alone. The committed `home benq 32 only`, `benq 32 above`,
and `benq 32 mirrored` profiles all match the laptop panel plus the BenQ
RD320U, so explicitly apply the desired external layout:

```bash
hyprmoncfg apply "home benq 32 only"
hyprmoncfg apply "benq 32 above"
hyprmoncfg apply "benq 32 mirrored"
```

`home dell 27 only` is the only profile for the Dell U2725QE (laptop panel
off, 4K at 120 Hz, 1.33333x scale — a 2880x1620 logical workspace), so the
daemon selects it
automatically whenever that monitor is connected.

The BenQ RD320U uses a sharp 1.06667x scale (3600x2025 logical workspace) in
each BenQ profile. This keeps the display readable while reducing the
input latency observed at 1.25x fractional scaling.

`hyprmoncfg` generates the active `~/.config/hypr/hyprmoncfg-monitors.lua`
itself. Do not commit or manually edit that file: `hyprland.lua` loads it with
`dofile(os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua")` at the
end of the file (after everything else, so nothing can override the applied
layout), and the daemon rewrites it as profiles change. (Older `hyprmoncfg`
versions wrote `~/.config/hypr/monitors.lua` instead; that file is no longer
generated or loaded, so it can be deleted if one is still lying around.)

`hyprmoncfg` owns that loader line. Since 1.17 it writes a guarded form — open the
file, `dofile` it only if it exists — and verifies after every reload that its
rules ran, rewriting the line at the end of `hyprland.lua` if not. Keep it verbatim:
editing it only earns a rewrite on the next apply. Because the target is generated
and gitignored it is absent on a fresh bootstrap, and the guard makes that a no-op,
so the static fallback rules in `hyprland.lua` apply until the first profile does.

Keep one profile per real desk, dock, projector, or travel setup; every JSON
profile is considered when the daemon chooses a match.

## Clamshell mode (lid closed, external monitor only)

With the lid closed, `hyprmoncfgd` turns the laptop panel off whichever profile
it picks (its closed-lid policy disables every internal output once an external
monitor is connected), so any matching profile becomes external-only. With the
lid open, the profile with the most enabled outputs wins, so for the BenQ that
is `benq 32 above` rather than `home benq 32 only`.

Lid close on external power is ignored (`linux/configs/logind/initd-lid-switch.conf`,
installed into `/etc/systemd/logind.conf.d/` by `linux/setup.sh:configure_lid_switch`).
logind's own docked check is not enough here. It skips the lid suspend only while
an external display is connected *and enabled*, and Hyprland's DPMS off disables
the output entirely. So hypridle's screen-off at 630 s made the monitor look
absent, and logind suspended a closed laptop about two minutes later, with no lid
event. Resume then raced the monitor's USB-C link renegotiation (the Dell drops
off DP and its USB hub for ~15 s) while hyprlock held the session, leaving a lit
but unresponsive screen. On battery, closing the lid still suspends.

Two things this does not cover:

- A laptop that is closed on battery is asleep. It used to stay asleep when a
  monitor was plugged in, until the lid opened: the kernel had wakeup disabled
  on every USB root hub and on the Bluetooth controller.
  `linux/configs/udev/90-initd-wakeup.rules` (installed by
  `linux/setup.sh:configure_wakeup_sources`) enables both. Plugging in the USB-C
  monitor connects its USB hub, which wakes the laptop, and the monitor's power
  delivery means logind leaves the closed lid alone. A Bluetooth keyboard key
  wakes it too. Check with `cat /sys/bus/usb/devices/usb*/power/wakeup` (all
  `enabled`).
- A closed laptop on a charger with no monitor stays awake, with the panel on
  until hypridle's screen-off.

## Recovering a stuck lock screen

If the monitor is on but nothing responds after a resume or a hotplug, the
session is most likely still locked with no lock surface on the screen you are
looking at. `misc.allow_session_lock_restore = true` in `hyprland.lua` lets a
fresh hyprlock take the lock over, so nothing has to be logged out:

1. Press `Ctrl+Alt+F3` and log in on the text console.
2. Look before changing anything (useful if this needs reporting):

   ```bash
   pgrep -a hyprlock
   hyprctl --instance 0 monitors
   ```

3. Replace the lock client:

   ```bash
   pkill -x hyprlock
   hyprctl --instance 0 dispatch 'hl.dsp.exec_cmd("hyprlock")'
   ```

4. Press `Ctrl+Alt+F2` to return to the Hyprland session (it runs on VT 2) and
   unlock as usual. Log out of the console afterwards with `exit`, from `Ctrl+Alt+F3`.

If `hyprctl` itself hangs, Hyprland is frozen rather than locked, and no lock
client can fix that. Short-press the power button for a clean shutdown (logind
treats it as power-off), and grab
`/run/user/1000/hypr/*/hyprland.log` from the console first, since a reboot
wipes it.

## Hyprland dies when a monitor is plugged in

Symptom: plugging in the Dell U2725QE kills Hyprland, and `start-hyprland`
restarts it in safe mode (default config, no bar or keybinds). The journal shows
`Couldn't waitpid for hyprland: No child processes` followed by
`Hyprland exit not-cleanly, restarting`. There is no Hyprland core dump and no
`~/.cache/hyprland/hyprlandCrashReport*.txt`.

Cause: since 0.57 Hyprland asks rtkit for realtime scheduling and accepts
`RLIMIT_RTTIME` in exchange: 150 ms soft / 200 ms hard of CPU without blocking
(`grep -i realtime /proc/$(pgrep -x Hyprland)/limits`). Bringing up a 4K@120
output on hotplug overran it, and the kernel's SIGKILL at the hard limit leaves
none of the usual traces. That `waitpid` line is how start-hyprland reports a
child killed by a signal rather than one that exited. Startup with the monitor
already attached survives, because realtime is requested after the first
modeset.

Fix: `hl.env("HYPRLAND_NO_RT", "1")` in `hyprland.lua`. Hyprland reads it once
at startup, so log out and back in after changing it, then check with
`ps -o cls -p $(pgrep -x Hyprland)` (`TS` means realtime is off, `RR` means it is on).
