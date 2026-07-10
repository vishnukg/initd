# Linux power management

This laptop balances performance and battery automatically: plug in and it
relaxes toward speed, unplug and it tightens toward runtime — with no daemon to
babysit and a one-key override when you want it. This doc explains the moving
parts, why each exists, and how to change the behavior.

The whole thing is built on **power-profiles-daemon** (PPD), the same power
backend GNOME and KDE use. We don't run TLP or auto-cpufreq — both would fight
PPD for control of the CPU, and PPD is the lighter, distro-blessed default.

## The hardware reality (why nothing here touches the governor)

The CPU is an Intel Core Ultra 7 155H (Meteor Lake). It uses the modern
`intel_pstate` driver in **active** mode, which means power management happens
in hardware (HWP) and is steered by a knob called **EPP** —
energy_performance_preference — rather than by the classic CPU governor.

A common trap: `cat .../scaling_governor` shows `powersave`, and people assume
that pins the CPU slow. It does not. On `intel_pstate` active mode the
`powersave` governor uses the **full** frequency range; EPP is what biases the
silicon toward power or speed. So the right lever is EPP, and **PPD is exactly
the thing that drives EPP for you**. That's why this setup never writes a
governor or a fixed frequency — doing so would be fighting the hardware.

```
intel_pstate (active)
  └─ governor: powersave        ← full freq range, NOT a slow pin
       └─ EPP: power ↔ performance   ← the real knob
            ▲
            └─ power-profiles-daemon sets this per profile
```

## The three profiles

`powerprofilesctl` is the CLI for PPD. Three profiles exist:

| Profile        | EPP bias         | Turbo        | Use                                  |
| -------------- | ---------------- | ------------ | ------------------------------------ |
| `power-saver`  | `power`          | curbed       | On battery — longest runtime         |
| `balanced`     | `balance_power`  | on           | Everyday default — the middle ground |
| `performance`  | `performance`    | on, eager    | Plugged in and you need full speed   |

```bash
powerprofilesctl get          # current profile
powerprofilesctl list         # all profiles, * marks active
powerprofilesctl set balanced # switch manually
```

## Automatic AC ↔ battery switching

On GNOME/KDE, PPD flips to `power-saver` on unplug automatically. **i3 has no
such logic** — left alone, PPD would sit on one profile forever regardless of
whether you're plugged in. This repo adds that missing piece with a udev hook.

### How it works

```
plug / unplug  ─▶  udev event (power_supply add/change)
                     │
                     ▼
            /usr/local/bin/power-profile-switch.sh
                     │  detects AC vs battery
                     ▼
            powerprofilesctl set balanced | power-saver
```

- **Plug in →** `balanced`
- **Unplug →** `balanced` (was `power-saver`; on the 155H that capped app
  launches hard enough to feel laggy — use `$mod+p` when you need max runtime)
- i3 also runs the switcher once at login (`exec_always`), so the profile is
  correct the moment your session starts, not just after the next plug event.

### AC detection is deliberately robust

The switcher doesn't trust a single sensor. It checks **any Mains-type adapter**
for `online=1` first, then falls back to **battery charge status** (`Charging` /
`Not charging`). That second path matters because this laptop can charge over
**USB-C PD**, where the legacy `ADP1` Mains sensor may stay `offline` even while
power is flowing. Either signal counts as "on AC."

### The polkit rule, and why it's required

The udev hook runs as **root with no active login session**. PPD's default
polkit policy only grants profile switches to an *active* session
(`allow_active = yes`); a sessionless caller falls under `allow_inactive`, which
is `auth_admin` — it would silently prompt for a password that no one can
answer, and the switch fails.

So we install a polkit rule (`49-power-profiles.rules`) that allows the
`switch-profile` / `hold-profile` actions unconditionally. Without it, the
automatic switching appears installed but never actually changes anything.

The **manual** controls below don't need this rule: they run inside your active
i3 session, where `allow_active = yes` already applies.

## Manual override

Automatic switching picks sensible defaults, but when you're about to do a heavy
build — or want to force quiet/cool on battery — override it:

- **`$mod+p`** cycles `power-saver → balanced → performance`, with a desktop
  notification showing the new profile.
- The **polybar indicator** (between backlight and battery) shows the current
  profile as an icon — leaf = power-saver, scale = balanced, bolt =
  performance. **Left-click also cycles.**

The override isn't sticky against reality: the next plug/unplug re-runs the
auto-switcher, so a manual bump to `performance` returns to the default once you
change power state. That's intended — you reach for the override in the moment,
and the machine quietly takes the wheel again afterward.

## Files

System files (installed by `linux/setup.sh` → `install_power_profile_autoswitch`,
need sudo):

| Source (`linux/scripts/`)     | Installed to                              | Role                                          |
| ----------------------------- | ----------------------------------------- | --------------------------------------------- |
| `power-profile-switch.sh`     | `/usr/local/bin/`                         | Detects AC/battery, sets the profile          |
| `99-power-profile.rules`      | `/etc/udev/rules.d/`                      | Fires the switcher on power_supply events     |
| `49-power-profiles.rules`     | `/etc/polkit-1/rules.d/`                  | Lets the sessionless root switch be permitted |

Session scripts (symlinked into `~/.config/` by `link_session_scripts`, no sudo):

| Source (`linux/scripts/`)     | Linked as                          | Role                                |
| ----------------------------- | ---------------------------------- | ----------------------------------- |
| `power-profile-cycle.sh`      | `~/.config/power-profile-cycle.sh` | `$mod+p` / polybar-click cycle      |
| `power-profile-status.sh`     | `~/.config/power-profile-status.sh`| Prints the icon for the polybar module |

Wiring: the `$mod+p` bind and login sync live in `linux/configs/i3/config`; the
`[module/powerprofile]` block lives in `linux/configs/polybar/config.ini`.

## Changing the defaults

The AC and battery targets are two variables at the top of
`linux/scripts/power-profile-switch.sh`:

```sh
AC_PROFILE=balanced
BATTERY_PROFILE=balanced
```

Want full speed whenever you're docked? Set `AC_PROFILE=performance`. Want
longer battery runtime at the cost of noticeably slower app launches? Set
`BATTERY_PROFILE=power-saver`. After editing, reinstall the system copy:

```bash
sudo install -m755 linux/scripts/power-profile-switch.sh /usr/local/bin/power-profile-switch.sh
/usr/local/bin/power-profile-switch.sh   # apply now
```

## Troubleshooting

**Profile never changes on plug/unplug.** Check the udev rule and switcher are
installed, and that the polkit rule is present — without it the sessionless
switch is denied silently:

```bash
ls /etc/udev/rules.d/99-power-profile.rules \
   /usr/local/bin/power-profile-switch.sh \
   /etc/polkit-1/rules.d/49-power-profiles.rules
sudo udevadm control --reload-rules
/usr/local/bin/power-profile-switch.sh && powerprofilesctl get   # run by hand
```

**Watch udev fire it live** while you plug/unplug:

```bash
udevadm monitor --subsystem-match=power_supply
```

**Profile resets unexpectedly.** That's the auto-switcher doing its job on a
power-state change — a manual override is meant to be transient. Edit the
defaults (above) if you want a different resting behavior.

**Confirm the hardware path** is the modern one this all assumes:

```bash
cat /sys/devices/system/cpu/intel_pstate/status                       # expect: active
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference # the live EPP
```

## What we deliberately did *not* install

- **TLP** — conflicts with PPD; you'd have to pick one.
- **auto-cpufreq** — fully-automatic governor switcher, but it must displace
  PPD, lives outside apt, and removes the manual `performance` profile. Its
  battery win over PPD's `power-saver` is usually small on a well-behaved modern
  laptop, and this machine already is one.

The biggest real-world battery lever isn't the CPU at all — it's **screen
brightness**, then this AC/battery auto-switch. The CPU side is already tuned by
`intel_pstate` + EPP; PPD just aims it.
