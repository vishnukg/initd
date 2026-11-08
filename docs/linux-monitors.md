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

## The Dell runs at 4K 60 Hz, not 120 Hz

Since 2026-11-08 the Dell U2725QE's profile and its fixed rule in
`hyprland.lua` ask for `3840x2160@60`. 120 Hz worked only in some cases, and
the kernel's debug log (`drm.debug=0x114`) shows why:

- 4K at 120 Hz is a 1188 MHz pixel clock. One display pipe on this laptop's
  Wildcat Lake iGPU cannot drive that, so the xe driver has to join two pipes
  (A+B). Whenever the laptop panel holds pipe B the commit is refused
  (`secondary is enabled as normal CRTC, but ... claiming this CRTC for
  joiner`, atomic check `-22`). Plugging the Dell in with the lid open
  therefore never got 120 Hz; it only came up when the laptop resumed with
  the lid already closed and the panel off. A plug-in with the lid open once
  turned the panel off while the Dell was refused, leaving both screens dark.
- After the Fedora 45 upgrade on 2026-11-08, 120 Hz was refused in every
  path tried (lid closed, resume, 2 and 4 lanes) with no kernel-side reason
  logged; Hyprland and aquamarine were the same upstream versions. That was
  not chased further: 60 Hz needs one pipe, so it works in any order, lid
  open or closed, with the panel on or off.
- The laptop has no Thunderbolt, so the Dell runs DisplayPort alt mode. Its
  **USB-C Prioritization** setting decides the lane split: High Data Speed
  gives 2 lanes (`pin assignment: D`) plus USB 3 on the Dell's hub; High
  Resolution gives 4 lanes (`pin assignment: C`) and drops the hub to USB 2.
  4K 60 Hz uses about 99% of 2 lanes uncompressed, and on 2026-11-08 one
  60 Hz fallback on 2 lanes trained the link and still showed nothing; on 4
  lanes it has room to spare. If the Dell is ever black at 60 Hz, switch the
  setting to High Resolution first.

If 120 Hz is ever wanted back, the profile also has to be applied with the
panel off first, and the starting point is booting the last Fedora 44 kernel
to split kernel from userspace.

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
and DRM debug logging for one night (`echo 0x04 | sudo tee
/sys/module/drm/parameters/debug`, off again at the next boot). On the monitor
itself, Personalize → **Fast Wakeup** must be On; the user guide describes it
as "Speed up recovery time from sleep mode", and it was found **Off** on this
Dell on 2026-11-05, the same day as the upgrade, so the two fixes went in
together. A monitor reset to factory settings loses it again.

Neither was the fix. With 1.28 running and Fast Wakeup on, the same day: an
81-minute display sleep (lid closed, charger, no suspend) woke dark again,
with the daemon applying the Dell profile error-free, the compositor's log
showing DP-1 modeset to 3840x2160@120 with no refused commit, and hyprlock
logging the password typed into a screen nobody could see; the next sleep,
six hours long, woke fine, with the kernel (debug on by then) logging
`Link Training passed` through the cable's LTTPR. So it is intermittent,
not a function of time asleep, and it sits below Hyprland. The one thing the
kernel log shows only while the Dell sleeps: with every output off the xe
driver loses HPD and falls back to polling, and each poll (every 5-10 s,
3,127 times in that six hours) connects the USB-C port (`TC port mode reset
(disconnected -> dp-alt)`), reads the DPCD and EDID, and releases it again.
A wake that lands inside one of those cycles is the leading suspicion; the
log of a failing wake with `drm.debug=0x04` on is what would confirm it, and
is the next thing to collect. Until then: if the Dell stays dark, do not
unplug; open the lid and read `ddcutil --bus 14 getvcp D6` and the kernel's
link-training lines from the moment of the wake.

Three more things about sleep, wake and the lid:

- **Plugging the monitor into a sleeping, closed laptop wakes it.**
  `linux/configs/udev/90-initd-wakeup.rules` (installed by
  `linux/setup.sh:configure_wakeup_sources`) enables wakeup on the USB root
  hubs, so the Dell's hub coming up on the cable wakes the machine, the
  profile applies with the panel off, and the Dell's power delivery keeps
  logind off the closed lid. Verified 2026-11-08: suspend at 16:59:49, the
  plug-in woke it at 17:00:28 with no lid event, profile applied 3 s later,
  steady picture at 4K 60 Hz. Opening and closing the lid (or the power
  button) still works as the fallback; a key on the Bluetooth keyboard does
  not wake it.

  This was first tried on 2026-11-04 (with the Bluetooth controller too) and
  retired the same day: the wake worked, but the Dell's picture then
  flickered until unplugged. The Dell ran at 4K 120 Hz then, which over the
  2-lane link needs DSC and two joined display pipes (see "The Dell runs at
  4K 60 Hz" above); at 60 Hz neither is involved and the flicker did not
  appear. The kernel still logs `typec port0-partner: PM: parent port0 should
  not be sleeping` on every such resume: the UCSI driver is busy during
  resume, which mainline a2463e2394 ("usb: typec: ucsi: allow retries of
  ucsi_resume_work", v7.4-rc1) addresses. If the plug-in wake ever starts
  flickering again, turn on DRM debug logging (`echo 0x114 | sudo tee
  /sys/module/drm/parameters/debug`) and read the link training, and retest
  on a 7.4 kernel before anything else. The Bluetooth controller never woke
  the machine (`/sys/bus/pci/devices/0000:00:14.7/power/wakeup_count`
  stayed 0), so that half of the old rule is not back.

- **A stuck USB-C controller keeps a closed laptop awake on battery.** On
  2026-11-08 the controller timed out one command right after a plug-in
  (`ucsi_handle_connector_change: GET_CONNECTOR_STATUS failed (-110)`), and
  from then on the UCSI driver saw no plug or unplug events: the Dell's
  power supply (`ucsi-source-psy-USBC000:001`) read `online=1` after it
  was unplugged, logind reported `OnExternalPower=true`, and closing the lid
  did nothing. The battery's own status read `Discharging` throughout, which
  is why `idle.sh can-suspend` now trusts that instead (so the 20-minute
  idle suspend still happens). To recover at once:
  `sudo modprobe -r ucsi_acpi && sudo modprobe ucsi_acpi` (or reboot).
  Upstream treats the timeout as controller firmware never completing a
  command; a Dell-specific extra-ACK workaround was proposed as an RFC.

  `hyprmoncfgd` runs at its default 2 s wake settle. Under 1.17 its drop-in
  carried `--wake-settle 8s`: 2 s had it pick a profile before a monitor
  arriving 4-5 s after resume existed, so a closed laptop got `laptop`
  (panel lit inside the lid) and the monitor profile a moment later, during
  link training. The cost was the other direction: every event during the
  settle restarts it, so opening the lid after an unplugged suspend showed
  the panel after 8-13 s. On 1.28 (hotplug debounce, wake retries) the
  plug-in resume was retested on 2026-11-05 at the default: the Dell was
  detected 0.6 s after resume, its profile applied 3.6 s after resume in one
  step, no refused commits, panel never lit. The override is gone.

  `hyprland.lua` also carries fixed rules for the Dell and the BenQ at their
  profiles' mode and scale. The generated file names only the outputs of the
  last profile, so a monitor hotplugged after `laptop` used to arrive through
  the catch-all rule at 60 Hz and be switched to 120 Hz seconds later, and
  hyprlock 0.9.7 lost its lock surface on that mode change. No upstream issue tracks that
  exact symptom; the nearest open report is
  [hyprwm/hyprlock#779](https://github.com/hyprwm/hyprlock/issues/779) (a crash
  while an external monitor is plugged in).
  With the rules it arrives in its final mode. If a profile's mode or scale is
  changed in `hyprmoncfg tui`, change the matching rule too.
- A closed laptop on a charger with no monitor stays awake, with the panel on
  until hypridle's screen-off.

## Recovering dead keybinds

If every Hyprland keybind stops responding at once (no terminal, no
launcher, no exit prompt) while the keyboard still types into windows, the
compositor is up and only its bind matching has been switched off. Three
things do that, and none needs a reboot:

- **A submap is active.** Only that submap's keys work; `resize`
  (`$mod+r`) is the one in this config, and `Return` or `Escape` leaves it.
- **A window holds a keyboard-shortcuts inhibitor.** Chromium-based
  browsers (Brave) request one when a page uses the keyboard-lock API,
  which they allow only in fullscreen; VMs and remote-desktop clients do
  too. Binds are dead while that window is focused and return when it is
  unfocused or closed. `binds:disable_keybind_grabbing = true` would refuse
  every such request; it is off here until this is seen to be the cause.
- **A stale press record.** Hyprland folds every key it still believes is
  held into the modifier mask it matches binds against, so a modifier whose
  release it never saw (a Bluetooth keyboard dropping mid-chord, say) makes
  every chord mismatch. Pressing and releasing that key clears it.

From a text console (`Ctrl+Alt+F3`, log in):

```sh
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t /run/user/1000/hypr | head -1)"
hyprctl dispatch 'hl.dsp.submap("reset")'   # 1. leave any submap
hyprctl -j clients | grep -E '"(class|fullscreen)"'   # 2. a fullscreen browser?
hyprctl dispatch 'hl.dsp.window.close()'    # 3. close the focused window
hyprctl dispatch 'hl.dsp.exit()'            # last resort: log out, not reboot
```

Then `Ctrl+Alt+F1` back to the session. On 2026-11-05 this happened once
(binds dead for ~3 min, a browser window closed a minute before a power-key
shutdown) and the cause was not recorded; the compositor keeps its log under
`/run/user/1000/hypr/<signature>/hyprland.log`, which a reboot erases, so
copy it from the console before restarting if it happens again:

```sh
cp /run/user/1000/hypr/*/hyprland.log ~/hyprland-deadkeys.log
```

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

## Shims, and when each can go

Three pieces of this setup exist only because something upstream is broken or
missing. Each is a plain switch or file, each is documented where it lives,
and each should be removed the day its condition below holds. Nothing else in
the display setup is tuned by hand: `hyprmoncfgd` runs with no flags, and the
timeouts in `hypridle.conf` are the schedule, not workarounds.

| Shim | Where | Why it exists | Remove when |
| --- | --- | --- | --- |
| `hl.env("HYPRLAND_NO_RT", "1")` | `linux/configs/hypr/hyprland.lua` | Hyprland 0.57 runs its main thread with a 200 ms realtime budget; a DisplayPort probe on the Dell's hotplug overran it and the kernel SIGKILLed the compositor (no core, safe-mode restart). [Hyprland discussion #16648](https://github.com/hyprwm/Hyprland/discussions/16648); Omarchy ships the same default. | A Hyprland release after 0.57.1 includes [PR #16843](https://github.com/hyprwm/Hyprland/pull/16843) (commit `b616b5474`, "init: stop acquiring realtime scheduling", merged 2026-11-04), which drops realtime entirely; the watchdog PR #16737 was closed in its favour. Test: drop the line, log in again, hotplug the Dell three times; `journalctl --user -b` must show no Hyprland restart. |
| `initd-hyprland-session.service` and the `systemctl --user start` of it in the `hyprland.start` block | `linux/configs/systemd/user/`, `hyprland.lua` | 0.57 starts `hyprland-session.target` itself, but the sdegler COPR installs it under `/usr/lib64/systemd/user/`, which is not on the user manager's unit path (`systemd-analyze --user unit-paths`). Without the shim `graphical-session.target` is never reached and hyprmoncfgd, Quickshell and the portals never start. | `systemctl --user list-unit-files hyprland-session.target` finds the unit after a package update. Then drop the service, its `MANAGED_LINKS` entry, the start line, and the five extra variables in the import. |
| Fixed `hl.monitor` rules for the Dell and the BenQ at their profiles' mode and scale | `hyprland.lua`, Monitors section | hyprmoncfg's generated file names only the active profile's outputs, so a monitor hotplugged after `laptop` arrived through the catch-all at 60 Hz and was switched to 120 Hz seconds later; hyprlock loses its surface on that mode change. | hyprmoncfg emits rules for every saved profile's monitors (worth a feature request), or hyprlock survives a mode change. No issue tracks that (the nearest is [hyprwm/hyprlock#779](https://github.com/hyprwm/hyprlock/issues/779)), so test it on a new hyprlock release: drop the two rules, lock on the `laptop` profile, plug the Dell in, and the lock screen must still draw on it once it switches to 120 Hz. Until then, a mode or scale change in `hyprmoncfg tui` must be mirrored in the rule. |

Retired so far: the `--wake-settle 8s` override (1.17 → 1.28, 2026-11-05), the
USB/Bluetooth wake rule (2026-11-04), the DPMS keybind and the retrain idea
(never shipped).
