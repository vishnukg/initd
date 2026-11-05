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

Quick settings' Displays page is a profile switcher: a read-only list of
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

**A monitor that stays dark after a long display sleep** (2026-11-05): left
plugged in and closed overnight, the laptop never suspended (on the charger
hypridle's suspend step does not fire, by design), hypridle turned the display
off at 630 s, and eleven hours later the Bluetooth keyboard woke the session:
hypridle sent DPMS on, the kernel saw a hotplug and reported DP-1 connected
with a CRTC, hyprlock was alive, mouse clicks reached the compositor, and the
Dell stayed black. Nothing on the software side logged an error. A 45-minute
dark period the evening before had woken fine. Unplugging then suspended the
laptop (charger gone, lid closed, logind's battery rule) and opening the lid
resumed it, which is why that "worked". This is upstream hyprmoncfg issue #67,
"outputs wake modeless after DPMS display sleep", and the fixes are in
hyprmoncfg 1.20–1.25: the wake is retried while a display still reports off,
the laptop panel is lit with a real mode when no external shows a picture
(that is what brought another lid-closed Intel laptop's external back), and an
enabled display that never wakes rolls the apply back. The paolino COPR stopped
at 1.17.0, so `linux/scripts/hyprmoncfg-install.sh` now installs the upstream
release rpm. If it happens again on 1.28+, the next step is diagnosis, not a
workaround: `ddcutil detect` / `ddcutil getvcp D6` from the laptop panel
(a monitor that answers DDC has a live link and a standby problem of its own),
and DRM debug logging for one night (`echo 0x1e | sudo tee
/sys/module/drm/parameters/debug`, off again at the next boot). On the monitor
itself, Personalize → **Fast Wakeup** must be On; the user guide describes it
as "Speed up recovery time from sleep mode", and it was found **Off** on this
Dell on 2026-11-05, the same day as the upgrade, so the two fixes went in
together and the overnight test that followed does not tell them apart. A
monitor reset to factory settings loses it again.

Two things this does not cover:

- A laptop that is closed on battery is asleep, and plugging a monitor into it
  does not wake it. **Plug the monitor in, then open the lid and close it
  again** (or press the power button): the laptop resumes with the monitor
  already attached, and `hyprmoncfgd` applies its profile with the panel off.
  This has worked on every wake tried; the lock screen comes up on the
  monitor and unlocks there.

  Waking *by* the plug-in was tried on 2026-11-04 (a udev rule enabling
  wakeup on the USB root hubs and the Bluetooth controller) and retired the
  same day. The USB wake worked, but the Dell's DisplayPort link then comes up
  while the kernel is still resuming (`typec port0-partner: PM: parent port0
  should not be sleeping` marks that path) and the picture flickers until
  unplugged, even once the daemon's wake settle (below) had reduced the
  software side to a single profile apply. The Bluetooth controller never
  woke the machine at all (`/sys/bus/pci/devices/0000:00:14.7/power/wakeup_count`
  stayed 0). The same cable and monitor are fine on a MacBook, so it is the
  kernel's bring-up, not the hardware. If it is ever worth another go: turn
  on DRM debug logging (`echo 0x1e > /sys/module/drm/parameters/debug`),
  install `drm_info`, re-enable the root hubs' wakeup for one boot, and read
  the link training and `link-status` during the flicker; a DPMS off/on of
  the output (a link retrain) or a 60 Hz mode are the two things to try live.
  **Retest first on a 7.4 kernel**: mainline commit a2463e2394 ("usb: typec:
  ucsi: allow retries of ucsi_resume_work", in v7.4-rc1, not tagged for
  stable) fixes the UCSI driver losing connection-status changes when the
  USB-C controller is busy during system resume, which is this path. Fedora's
  `@kernel-vanilla/mainline-wo-mergew` COPR has it for F44 if it is wanted
  sooner (Secure Boot is off on this machine, so an unsigned kernel boots).

  `hyprmoncfgd` runs with `--wake-settle 8s` (its drop-in). With the default
  2 s it picked a profile before a monitor arriving 4-5 s after resume
  existed, so a closed laptop got `laptop` (panel lit inside the lid) and the
  monitor profile a moment later; every event during the settle restarts it,
  so 8 s gives one apply with the monitor present. The cost is ~8 s instead of
  ~2 s to the panel after opening the lid when the last profile had it off.

  `hyprland.lua` also carries fixed rules for the Dell and the BenQ at their
  profiles' mode and scale. The generated file names only the outputs of the
  last profile, so a monitor hotplugged after `laptop` used to arrive through
  the catch-all rule at 60 Hz and be switched to 120 Hz seconds later, and
  hyprlock 0.9.7 lost its lock surface on that mode change (hyprwm/hyprlock#678).
  With the rules it arrives in its final mode. If a profile's mode or scale is
  changed in `hyprmoncfg tui`, change the matching rule too.
- A closed laptop on a charger with no monitor stays awake, with the panel on
  until hypridle's screen-off.

## Recovering a stuck lock screen

If the monitor is on but nothing responds after a resume or a hotplug, the
session is most likely still locked with no lock surface on the screen you are
looking at. `misc.allow_session_lock_restore = true` in `hyprland.lua` lets a
fresh hyprlock take the lock over, so nothing has to be logged out. hypridle
starts hyprlock through `idle.sh lock`, which starts it again whenever it dies
from a signal: a crash, or the `pkill` below. A dead client never unlocks the
session.

1. Press `Ctrl+Alt+F3` and log in on the text console.
2. Look before changing anything (useful if this needs reporting):

   ```bash
   pgrep -a hyprlock
   hyprctl --instance 0 monitors
   ```

3. Replace the lock client. `idle.sh lock` restarts it within a second. Run the
   second command only if `pgrep -a hyprlock` shows nothing a moment later
   (for example, after five crashes in a row it stops trying):

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
