# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the behavior test suite (auto-detects host OS; uses temporary home directories)
shared/test.sh

# Syntax-check every script
bash -n bootstrap.sh \
  shared/lib/logging.sh shared/lib/fs.sh \
  shared/lib/link.sh shared/lib/cleanup.sh shared/lib/git-profile.sh \
  shared/managed-links.sh shared/test.sh \
  macos/bootstrap.sh macos/defaults.sh macos/brewinstall.sh macos/update.sh macos/managed-links.sh \
  linux/bootstrap.sh linux/setup.sh linux/update.sh linux/managed-links.sh

# Full bootstrap (dispatches by uname)
bash bootstrap.sh

# Re-apply managed symlinks only
shared/lib/link.sh macos    # or: linux

# Set the Git identity (personal = default email; work = write override to local.gitconfig)
shared/lib/git-profile.sh personal
shared/lib/git-profile.sh work

# Preview / run cleanup
shared/lib/cleanup.sh <platform> --dry-run
shared/lib/cleanup.sh <platform>

# macOS — add a Homebrew package to the curated Brewfile and install it locally
macos/brewinstall <package>           # auto-detects formula vs cask
macos/brewinstall --cask <package>
macos/brewinstall --formula <package>

# Update tools (per platform)
macos/update.sh
linux/update.sh
```

## Architecture

Three top-level buckets, intentionally decoupled. The contract: `shared/` must not branch on OS; if it would need to, push that branch into the platform script.

```
initd/
├── bootstrap.sh              # ~20-line dispatcher: uname -s → macos|linux
├── shared/                   # cross-platform — sourced by both bootstraps
│   ├── lib/                  # logging.sh, fs.sh, link.sh, cleanup.sh, git-profile.sh
│   ├── managed-links.sh      # MANAGED_LINKS for shared configs + git helpers
│   ├── configs/              # fish, git, ghostty, mise, nvim, starship, tmux
│   └── test.sh
├── macos/                    # self-contained — `rm -rf macos/` and Linux still works
│   ├── bootstrap.sh
│   ├── Brewfile
│   ├── brewinstall, brewinstall.sh
│   ├── defaults.sh           # macOS defaults write …
│   ├── managed-links.sh      # appends macOS-only links to MANAGED_LINKS
│   └── update.sh
└── linux/                    # self-contained — `rm -rf linux/` and macOS still works
    ├── bootstrap.sh          # targets Fedora Workstation 44+ (dnf5); some packages come from COPR
    ├── packages.txt          # dnf package list (one per line) — Wayland/Hyprland stack
    ├── setup.sh              # system fixes (fonts, theme/config glue)
    ├── managed-links.sh      # appends hypr/quickshell/rofi/dunst links
    ├── update.sh
    ├── scripts/              # session scripts invoked by Hyprland/Quickshell
    └── configs/              # hypr, quickshell, rofi, dunst, gtk, firefox, …
```

### Execution flow

```
bootstrap.sh
  └─ exec macos/bootstrap.sh                  # if uname=Darwin
  └─ exec linux/bootstrap.sh                  # if uname=Linux

macos/bootstrap.sh
  ├─ ensure_xcode_clt
  ├─ ensure_homebrew
  ├─ brew bundle --file macos/Brewfile
  ├─ shared/lib/link.sh macos                 # symlinks
  ├─ ensure_gh_auth, ensure_fish (dscl)
  ├─ mise install
  ├─ macos/defaults.sh
  ├─ setup_git_profile (uses shared/lib/git-profile.sh)
  ├─ ensure_docker_config                 # merges credsStore=osxkeychain + brew cliPluginsExtraDirs into ~/.docker/config.json
  └─ ensure_colima_service                # brew services start colima (login autostart)

linux/bootstrap.sh
  ├─ ensure_user_context, ensure_fedora
  ├─ install_packages                          # enables sdegler/hyprland,
  │                                               paolino/hyprmoncfg, and scottames/ghostty COPRs,
  │                                               then dnf-installs
  │                                               packages.txt + the C Development Tools group
  ├─ ensure_gh (official dnf repo), ensure_1password (official dnf repo),
  │  ensure_docker (Docker's official dnf repo), ensure_mise (curl mise.run)
  ├─ shared/lib/link.sh linux                 # symlinks
  ├─ linux/setup.sh                           # fonts/theme + config glue
  ├─ ensure_gh_auth, ensure_fish (chsh)
  ├─ mise install
  └─ setup_git_profile
```

### Script sourcing chain

```
shared/lib/logging.sh           ← must be first; defines log_*, require_command, INITD_* color vars
shared/lib/fs.sh                ← filesystem helpers; requires logging.sh first
shared/managed-links.sh         ← MANAGED_LINKS (shared); requires ROOT_DIR
<platform>/managed-links.sh     ← appends to MANAGED_LINKS; requires ROOT_DIR + initial MANAGED_LINKS
```

`ROOT_DIR` must be exported before sourcing `shared/managed-links.sh` because the array embeds absolute paths.

### MANAGED_LINKS — the ownership list

The single array `MANAGED_LINKS` is built in two steps:

1. `shared/managed-links.sh` defines the cross-platform entries (fish, ghostty, mise, nvim, starship, tmux).
2. `<platform>/managed-links.sh` appends OS-only entries (currently nothing on macOS; hypr/quickshell/rofi/dunst/gtk-3.0 on Linux).

Entry format: `"home path:repo path"`. Scripts split with `home_path="${entry%%:*}"` / `repo_path="${entry#*:}"`.

`~/.gitconfig` is an ordinary `MANAGED_LINKS` entry pointing at the single `shared/configs/git/gitconfig`. That base config bakes in the default (personal) Git email and `[include]`s `shared/configs/git/local.gitconfig` *after* the `[user]` block, so a work email written there overrides the default. `shared/lib/git-profile.sh personal|work` only decides whether that override file gets written — it no longer switches what `~/.gitconfig` links to.

**Adding a managed config:**
- Cross-platform: add to `MANAGED_LINKS` in `shared/managed-links.sh` and place the source under `shared/configs/<name>/`.
- Platform-only: append to `MANAGED_LINKS` in `<platform>/managed-links.sh` and place the source under `<platform>/configs/<name>/`.

Then add a corresponding assertion in `shared/test.sh` (or rely on the generic `get_managed_links` loop, which iterates over whatever the host platform produces).

### Machine-local secrets

Two files are gitignored and never committed:

| File | Purpose |
|---|---|
| `shared/configs/git/local.gitconfig` | Work (or other) Git email override; absent on personal machines |
| `shared/configs/fish/.config/fish/local.fish` | Machine-specific env vars and overrides |

Both follow the same pattern: sourced/included at startup if present, silently skipped if absent.

### Dotfile layout convention

Each managed package lives in a subdirectory that mirrors `$HOME`:

```
shared/configs/fish/.config/fish/    →  symlinked as ~/.config/fish
shared/configs/tmux/.config/tmux/    →  symlinked as ~/.config/tmux
linux/configs/hypr/                  →  symlinked as ~/.config/hypr
linux/configs/quickshell/            →  symlinked as ~/.config/quickshell
```

For shared/ the path inside the package mirrors `$HOME` exactly. For linux/ the configs live directly under `linux/configs/<name>/` (no `.config` prefix) because the source path is already namespaced by platform.

Edit files inside this repo, not through the live symlinks.

### Backup safety

`backup_path` in `shared/lib/fs.sh` moves any pre-existing unmanaged file to `${BACKUP_ROOT}/<relative-path>` before taking ownership. `BACKUP_ROOT` is exported by each platform's `bootstrap.sh` so re-applying links uses the same timestamped folder for the whole run.

### Line endings

`.gitattributes` enforces `eol=lf` for `*.sh`, `*.fish`, `*.conf`, `*.ini`, and other text files so commits from any host (including Windows) land as LF — the only line-ending bash and `/etc/`-style configs can parse on macOS or Linux.

### Linux-specific quirks

The Linux desktop is **Wayland-only**: Hyprland installed alongside Fedora's stock GNOME (both offered at the GDM login screen). Fedora's own repos don't carry the Hyprland ecosystem, `hyprmoncfg`, or `ghostty` — `install_packages()` enables their three COPRs first (`sdegler/hyprland`, `paolino/hyprmoncfg`, `scottames/ghostty`) before resolving `packages.txt`. The old X11 stack (i3, polybar, picom, xsettingsd, autorandr, Xresources) and the previous Ubuntu-specific fixes (Intel WiFi/Bluetooth udev rules, WiFi regdomain, power-profile AC/battery auto-switch, Chrome apt-arch pin) have been removed from the repo; git history has them if ever needed. This machine is different hardware from the old Ubuntu laptop those fixes targeted, and the trimmed-down setup intentionally doesn't try to guess replacements — add back only what a given machine actually needs.

- **Hyprland config** (`linux/configs/hypr/hyprland.lua`): Hyprland's Lua config format (hyprlang `.conf` support is removed entirely in Hyprland 0.57; this repo ported fully rather than keep a config format on a deprecation countdown). Per-monitor scale (laptop panel 1.25x, externals 1.25x) via `hl.monitor({...})`, with generated profile rules loaded from `hyprmoncfg-monitors.lua`; built-in blur/rounding/animations; `kb_options = ctrl:nocaps` and `repeat_delay/rate` for input. The polkit auth agent is `lxpolkit` (Fedora has neither `polkit-gnome` nor a `hyprpolkitagent` package). Hyprland only detects `hyprland.lua` vs `hyprland.conf` at compositor **startup**, not on `hyprctl reload` — use `Hyprland --verify-config --config <path>` to validate changes without restarting. **Every dispatch payload is Lua too**, over `hyprctl` and over the IPC socket alike: `hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })'`, not `hyprctl dispatch workspace 2`. Quickshell's convenience wrappers (`HyprlandWorkspace.activate()`) still emit the legacy syntax and fail with a log warning rather than an error, so the bar sends Lua strings through `Hyprland.dispatch()` instead.
- **Ghostty runs as a terminal server on Linux**: Fedora's packaged `app-com.mitchellh.ghostty.service` is enabled by `linux/setup.sh:enable_ghostty_server`, so one Ghostty process owns every window and `$mod+Return` (`ghostty --gtk-single-instance=true`) asks it for one instead of starting a terminal cold — 574ms to ~250ms, measured. Flags live in `linux/configs/systemd/user/app-com.mitchellh.ghostty.service.d/override.conf`, a drop-in over the vendor unit, because **a single-instance client forwards only the request: config flags passed to the client are silently dropped** (`--background-opacity`, `--title` and `--class` all no-op). That is why the Linux-only 0.92 opacity sits on the *server* command line; `shared/configs/ghostty/` is shared with macOS and is never edited for Linux reasons. The keybind still passes `--background-opacity` so it degrades to a readable terminal if no server is running. Two consequences: after editing the shared Ghostty config, run `systemctl --user reload app-com.mitchellh.ghostty.service` (`Type=notify-reload`, `SIGUSR2`); and since all windows are one process, killing it closes every terminal at once — tmux sessions survive, bare shells do not.
- **Companion stack**: Quickshell (`shell.qml`) provides the Hyprland bar, Wi-Fi/Bluetooth status, system tray, audio, battery, metrics, weather, and Docker status; rofi 2.0 (`config.rasi`), dunst (`dunstrc`), hyprlock + hypridle, hyprpaper (wallpapers committed at `shared/wallpaper/`, linked to `~/.local/share/wallpapers`), grim/slurp, wl-clipboard.
- **Weather icons**: the bar asks wttr.in for `%C|%t|%S|%s` — condition *name*, not `%c`'s colour emoji — and `weatherIcon()` maps that name to a Nerd Font `nf-md-weather-*` glyph, so weather looks like every other bar icon. The keyword tests run in severity order (thunder → ice → fog → sleet/freezing → snow → rain → cloud → clear); order matters, e.g. fog is checked before "freezing" so "Freezing fog" isn't drawn as sleet. `%S`/`%s` (sunrise/sunset) pick the sun-vs-moon variant for clear and partly-cloudy skies.
- **Bar colour**: `BarItem` has a single `foreground`, so colour is per item, not per glyph — icon and number always match. Colour means *state*, never decoration: `weatherColor()` is a temperature ramp that stays flat through the mild band (12–25 °C), deepens through blue below 12 °C and through amber to red above 25 °C, reading the unit off the string so a °F reading converts first, `loadColor()` ramps CPU and memory neutral → amber at 70% → red at 90%, and battery, power profile and audio-mute keep their own. Docker, brightness and the clock are deliberately flat `#e8eaf0` — a count and a backlight level have no severity to signal.
- **Bar interaction model** (`BarItem.qml`): hovering an item shows a `BarTooltip` label below it — title plus current reading — and clicking is reserved for items that *do* something: the power-profile icon cycles power-saver/balanced/performance, Docker opens the rofi container menu, weather fires the wttr.in notification, audio opens `AudioMenu`. CPU, memory, brightness, and battery are hover-only. Tray items (Wi-Fi via nm-applet, Bluetooth via blueman) still open `TrayMenu` and the clock still opens `CalendarPopup` on click — dropdowns are for menus, tooltips are for readouts. Audio is the one item with a right-click too (`secondaryClickable`/`onSecondaryClicked` on `BarItem`): its left-click had to be handed to the device picker, so one-click mute moved to the right button rather than disappearing.
- **Audio device picker** (`AudioMenu.qml` + `DeviceRow.qml`): left-clicking the audio item opens a popup listing every PipeWire output and input endpoint; clicking one writes `Pipewire.preferredDefaultAudioSink`/`preferredDefaultAudioSource`, which is the *configured* default WirePlumber persists to `~/.local/state/wireplumber/default-nodes` — not a session-only override. `endpoints()` filters `Pipewire.nodes` by the composite `PwNodeType.AudioSink`/`AudioSource` flags and drops `isStream` nodes, so per-application streams and the output half of a filter chain stay out of the list. Devices are classified by **node name**, not `properties`: `properties` is only populated for nodes bound by a `PwObjectTracker` and this list deliberately binds none of them, whereas `name`/`nickname`/`description`/`isSink`/`type` are constant and readable unbound. The `deviceKind()` tests run in a fixed order because HDMI and USB endpoints are ALSA devices too — they must be matched before the generic `alsa_` test claims them as `Built-in`. Rows are grouped Built-in → USB → HDMI → Bluetooth → AirPlay → Virtual, so the laptop's own speaker and mic keep a stable position regardless of what is plugged in. Labels prefer the attached display's own name over `node.nickname` ("Speaker", "HDMI 1"), which in turn beats `description` (it repeats the sound card name); the kind tag on the right is what disambiguates two devices that both call themselves "Speaker". **Neither the display name nor the "is anything plugged in?" answer comes from PipeWire's node properties** — both hang off the sound card's *port* (`device.product.name`, lifted from the monitor's ELD, and the port's availability), and Quickshell's Pipewire service exposes nodes only, no devices and no routes. `linux/scripts/audio-ports.sh` shells out to `pactl list cards` for them and prints `<port>|<availability>|<display name>` per port, which `portProcess` turns into an ALSA-port map joined to an endpoint by the port token its name embeds between double underscores (`...HiFi__HDMI1__sink`). Empty ports are filtered out of both lists, so an unused HDMI socket is not a dead row you can select. Two rules keep that from hiding something real: only an explicit `not available` counts as empty (a port that cannot detect presence reports `availability unknown`, and the built-in speaker and mic report exactly that), and every lookup fails open — an endpoint the map says nothing about, which is every Bluetooth, AirPlay, and filter-chain node, is always shown and never renamed. The current default is kept in the list even if its port reads empty, so the checkmark always has somewhere to sit; in practice WirePlumber refuses to make an unavailable sink the default at all, so that guard is only covering the window where the map is stale. The script re-runs on every menu open rather than on a PipeWire signal, because plugging a monitor in or out does not change the sink set at all — all three HDMI sinks exist whether or not anything is attached.
- **Current suspend/lid behavior**: systemd-logind uses its default lid-close suspend policy. Hypridle requests a session lock through `loginctl` before sleep, which invokes `hyprlock`, then waits for Hyprland's session-lock confirmation (`inhibit_sleep = 3`) before releasing its delay inhibitor. `hyprmoncfgd` selects and applies monitor profiles for hotplug and lid events.
- **System fixes** that need sudo: `video` group membership (backlight is `root:video`; required for the XF86MonBrightness keybinds — takes effect after re-login) and disabling unused `ModemManager` (no modem on this hardware). These are applied by `linux/setup.sh`.
- **Firefox install is unmanaged, its profile is not**: no `ensure_firefox` step and no entry in `packages.txt` — install it however you like. Once present, `linux/setup.sh:link_firefox_profile` symlinks `linux/configs/firefox/user.js`, `chrome/userChrome.css`, and `chrome/userContent.css` into the active profile: native-window integration (titlebar merged into tabs, rounded CSD corners matching `decoration.rounding`), normal density, the built-in dark theme, and VAAPI hardware video decode. No forced extensions/policies. `set_firefox_default_zoom` sets 133% default zoom separately, via `content-prefs.sqlite` (the mechanism Firefox's own Zoom UI actually reads — a `user.js` pref like `layout.css.devPixelsPerPx` changes rendering density but never shows up in the Zoom menu, which is a common point of confusion). Needs Firefox fully closed to write safely; skips with a warning otherwise and retries next run.
- **Night light** (`linux/scripts/night-light-toggle.sh`): on Wayland the gamma table resets when the client exits, so gammastep runs as a persistent process while warm is active (the process itself is the state) instead of a one-shot mode.
- **Special-case paths**: `~/.gtkrc-2.0`, `~/.icons/default/index.theme`, and Firefox profile files (dynamic profile path) live outside `~/.config/` and are linked individually rather than via `MANAGED_LINKS`.
- **Theme fonts/cursors**: Fedora has no `fonts-ubuntu` or DMZ-cursor package, so `apply_gsettings_theme` uses `Adwaita Sans` and the `Adwaita` cursor theme (both always present) instead of the old Ubuntu-branded defaults.
- **Monitors**: `hyprmoncfg` owns monitor profiles, workspace assignments, hotplug, and lid changes. Its generated `hyprmoncfg-monitors.lua` is loaded via `dofile(...)` at the end of `hyprland.lua` (after everything else, so nothing can override the applied layout); profiles are versioned under `linux/configs/hyprmoncfg/`. See `docs/linux-monitors.md`.

### Reference docs

- `docs/bash-primer.md` — repo-specific Bash patterns
- `docs/fish.md` — fish/bash/zsh syntax comparison
- `docs/nvim.md` — Neovim plugin setup and Lazy.nvim usage
- `docs/mise.md` — mise tool management
- `docs/colima.md` — Colima (Docker without Docker Desktop) setup and daily use
- `docs/git-branching-conflicts.md` — Git branching and conflict resolution
- `docs/linux-monitors.md` — monitor hotplug/lid switching, manual per-monitor overrides, per-monitor scale
- `docs/tmux-nvim.md` — tmux and Neovim workspace concepts
- `docs/tmux-sessions.md` — tmux session/window/pane workflow and keybindings
