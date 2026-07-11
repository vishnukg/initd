# Linux monitor handling

How external monitors work on this setup, and the (tiny) ritual for a new one.

## The mental model

`autorandr` is a **layout memory**. Every monitor reports a hardware ID (EDID).
Whenever the set of connected screens changes — cable plugged/unplugged, lid
opened/closed — autorandr checks *"have I seen this combination before?"*:

- **Seen before** → applies your saved layout for it.
- **Never seen** → falls back to mirroring all screens (`clone-largest`), so a
  brand-new monitor always lights up immediately.

A closed lid makes autorandr treat the laptop panel as disconnected, which is
how "lid closed while docked = external only" works.

Every switch runs the postswitch hook (`linux/scripts/autorandr-postswitch.sh`):
per-profile DPI → xsettingsd (running GTK apps rescale live) → wallpaper
centered on each screen → polybar relaunched per monitor.

## Using a monitor you've already saved

Nothing to do. Plug/unplug/lid events apply the right profile automatically.

| Event | Result |
|---|---|
| Plug in known monitor | `docked` layout (extended, external primary) |
| Close lid while docked | external becomes the only screen |
| Open lid | back to the dual layout |
| Unplug | laptop screen takes over |

**Fix-it button:** `$mod+Shift+m` force-reapplies everything for the current
hardware state.

## Attaching a NEW monitor (once per monitor)

1. **Plug it in.** It mirrors your screen automatically. For a one-off
   projector/TV, stop here.
2. **Arrange it:** run `arandr`, drag the screen rectangles into position,
   *Layout → Apply*. (Or use `xrandr` directly.)
3. **Save it:**

   ```bash
   autorandr --save <name>          # e.g. office-dell
   ```

4. **Lid-closed variant** (only if you'll use it that way): close the lid —
   the external stays lit — then:

   ```bash
   autorandr --save <name>-closed
   ```

Done. The monitor is now fully automatic, like the primary BenQ.

## Useful commands

```bash
autorandr                 # list profiles; shows which is detected/current
autorandr --load <name>   # apply a profile manually
autorandr --save <name> --force   # overwrite after rearranging
$mod+Shift+m              # re-apply layout + DPI + wallpaper + polybar
```

## Where things live

| Thing | Location |
|---|---|
| Saved profiles (EDID fingerprints, machine-local, not in repo) | `~/.config/autorandr/<name>/` |
| Postswitch hook (DPI/wallpaper/polybar reflow) | `linux/scripts/autorandr-postswitch.sh` |
| Per-profile DPI values (laptop 144 / external 108) | top of `linux/scripts/display-dpi.sh` |
| Per-monitor polybar scaling + module list | `linux/configs/polybar/launch.sh` |
| `clone-largest` fallback (systemd drop-ins) | `linux/scripts/autorandr-*override.conf` → `/etc/systemd/system/` |
| Hotplug/lid plumbing (shipped by the autorandr package) | udev `40-monitor-hotplug.rules`, `autorandr-lid-listener.service` |

## DPI notes

X11 has **one global `Xft.dpi`** — no per-monitor value. `display-dpi.sh` sets
it per *profile*: `laptop`/`default` → 144, anything else → 108. New profile
names automatically get the compact 108. Polybar is the exception that gets
true per-monitor treatment (one bar process per screen, each scaled to its
panel; external bars drop the backlight module since sysfs brightness only
controls the laptop panel).
