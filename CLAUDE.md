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
    ├── setup.sh              # system fixes (fonts, swappiness, theme/config glue)
    ├── managed-links.sh      # appends hypr/waybar/rofi/dunst links
    ├── update.sh
    ├── scripts/              # session scripts invoked by hyprland.lua/waybar
    └── configs/              # hypr, waybar, rofi, dunst, gtk, firefox, …
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
  ├─ install_packages                          # enables sdegler/hyprland, tofik/nwg-shell,
  │                                               scottames/ghostty COPRs, then dnf-installs
  │                                               packages.txt + the C Development Tools group
  ├─ ensure_gh (official dnf repo), ensure_1password (official dnf repo),
  │  ensure_docker (Docker's official dnf repo), ensure_mise (curl mise.run)
  ├─ shared/lib/link.sh linux                 # symlinks
  ├─ linux/setup.sh                           # fonts/swappiness/theme + config glue
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
2. `<platform>/managed-links.sh` appends OS-only entries (currently nothing on macOS; hypr/waybar/rofi/dunst/gtk-3.0 on Linux).

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
linux/configs/waybar/                →  symlinked as ~/.config/waybar
```

For shared/ the path inside the package mirrors `$HOME` exactly. For linux/ the configs live directly under `linux/configs/<name>/` (no `.config` prefix) because the source path is already namespaced by platform.

Edit files inside this repo, not through the live symlinks.

### Backup safety

`backup_path` in `shared/lib/fs.sh` moves any pre-existing unmanaged file to `${BACKUP_ROOT}/<relative-path>` before taking ownership. `BACKUP_ROOT` is exported by each platform's `bootstrap.sh` so re-applying links uses the same timestamped folder for the whole run.

### Line endings

`.gitattributes` enforces `eol=lf` for `*.sh`, `*.fish`, `*.conf`, `*.ini`, and other text files so commits from any host (including Windows) land as LF — the only line-ending bash and `/etc/`-style configs can parse on macOS or Linux.

### Linux-specific quirks

The Linux desktop is **Wayland-only**: Hyprland installed alongside Fedora's stock GNOME (both offered at the GDM login screen). Fedora's own repos don't carry the Hyprland ecosystem, `nwg-displays`, or `ghostty` — `install_packages()` enables three COPRs first (`sdegler/hyprland`, `tofik/nwg-shell`, `scottames/ghostty`) before resolving `packages.txt`. The old X11 stack (i3, polybar, picom, xsettingsd, autorandr, Xresources) and the previous Ubuntu-specific fixes (Intel WiFi/Bluetooth udev rules, WiFi regdomain, power-profile AC/battery auto-switch, Chrome apt-arch pin) have been removed from the repo; git history has them if ever needed. This machine is different hardware from the old Ubuntu laptop those fixes targeted, and the trimmed-down setup intentionally doesn't try to guess replacements — add back only what a given machine actually needs.

- **Hyprland config** (`linux/configs/hypr/hyprland.lua`): Hyprland's Lua config format (hyprlang `.conf` support is removed entirely in Hyprland 0.57; this repo ported fully rather than keep a config format on a deprecation countdown). Per-monitor scale (laptop panel 1.25x, externals 1.25x) via `hl.monitor({...})`; `switch:on:Lid Switch` binds handle lid events; built-in blur/rounding/animations; `kb_options = ctrl:nocaps` and `repeat_delay/rate` for input. The polkit auth agent is `lxpolkit` (Fedora has neither `polkit-gnome` nor a `hyprpolkitagent` package). Hyprland only detects `hyprland.lua` vs `hyprland.conf` at compositor **startup**, not on `hyprctl reload` — use `Hyprland --verify-config --config <path>` to validate changes without restarting (note: it does execute the `config.reloaded` hook for real, so it's a dry-run for parsing/binds but not fully side-effect-free).
- **Companion stack**: waybar (auto-detects network/battery/backlight, so no hardware patching), rofi 2.0 (`config.rasi`), dunst (`dunstrc`), hyprlock + hypridle, hyprpaper (wallpaper committed at `linux/configs/wallpaper/wallpaper.jpg`), grim/slurp, wl-clipboard.
- **Current suspend/lid behavior**: systemd-logind uses its default lid-close suspend policy. Hypridle requests a session lock through `loginctl` before sleep, which invokes `hyprlock`, then waits for Hyprland's session-lock confirmation (`inhibit_sleep = 3`) before releasing its delay inhibitor. It has no `after_sleep_cmd`: a post-resume `hyprctl` DPMS dispatch caused `start-hyprland` to abort after an otherwise clean s2idle resume. The historical workaround note below is superseded and retained only as investigation history.
- **System fixes** that need sudo: `video` group membership (backlight is `root:video`; required for the XF86MonBrightness keybinds — takes effect after re-login) and disabling unused `ModemManager` (no modem on this hardware). These are applied by `linux/setup.sh`.
- **Suspend is disabled on lid close — temporary workaround, not permanent policy**: `linux/configs/systemd/logind.conf.d/10-lid-lock-only.conf` (installed by `linux/setup.sh:install_lid_lock_only`) sets `HandleLidSwitch(ExternalPower/Docked)=lock` instead of systemd's default `suspend`. Root cause: this hardware's Intel `xe` driver (Wildcat Lake) has a live, unfixed kernel bug where the Hyprland compositor hangs on s2idle resume — confirmed live via `hyprctl` timing out with `Hyprland IPC didn't respond in time` while the kernel itself reports a clean resume (`PM: resume devices took ...`, no errors). **Do not try `mem_sleep_default=deep` as a fix** — already tried, made it worse: this hardware's firmware has no working S3 resume path at all, and the machine hung completely (journal's last line was `PM: suspend entry (deep)`, no resume ever logged) requiring a hard power-off. **Do not reintroduce a systemd-sleep resume-kick hook either** — also tried (DPMS toggle + brightness restore in `/usr/lib/systemd/system-sleep/`, the only directory that mechanism actually reads — `/etc/systemd/system-sleep/` is silently never executed, confirmed via `man systemd-suspend.service` and `strings`). It ran correctly but couldn't fix anything: the compositor hang is exactly what makes its own `hyprctl` calls time out too. Removed once lock-only made it moot (nothing suspends on lid close anymore, so there's no resume to hook). `linux/scripts/clamshell.sh` compensates for lock-only losing DPMS-off-on-lid-close (logind's `lock` action only locks, it doesn't touch display power) by explicitly running `loginctl lock-session` + `hyprctl dispatch dpms off/on` on real lid events (guarded against firing again on a plain `hyprctl reload`). Trade-off of lock-only: real suspend's battery savings are gone while the lid is closed (CPU/RAM/WiFi keep running, same draw as a locked-but-awake desktop). **Remove once fixed upstream**: after a `dnf upgrade` brings a newer kernel, test a real multi-hour lid-close/reopen; if the compositor survives resume (no `hyprctl` IPC timeout, journal shows a clean `PM: suspend exit` and the session is still responsive), delete the logind.conf.d override and drop `install_lid_lock_only` from `linux/setup.sh` main() — the clamshell.sh lock/dpms lines are harmless to leave in place either way. This is a known, currently-unfixed upstream `xe` issue affecting this whole generation of Intel hardware, not something unique to this machine — see [a matching Lunar Lake s2idle-resume-freeze report](https://forum.level1techs.com/t/lunar-lake-thinkpad-x1-carbon-gen-13-xe-driver-freeze-on-s2idle-resume-fedora-43/246487) (suspected cause: GuC SLPC failing to reinitialize GPU frequency on resume; unconfirmed kernel 6.19 cleanup that might help) and [a Dell XPS Panther Lake issue](https://github.com/basecamp/omarchy/issues/5573) with the identical `Selective fetch area calculation failed in pipe A` dmesg line this machine also shows (different trigger — boot-time there, resume here — but confirms that line is a known active `xe` display-code bug signature on this generation, not machine-specific). No confirmed reliable fix exists yet as of this writing. A more specific mechanism was later found: `hyprlock` itself was seen SIGABRT-crashing on this machine at the exact moment of one resume hang, matching [hyprwm/hyprlock#1048](https://github.com/hyprwm/hyprlock/issues/1048) — hyprlock intermittently crashes on Intel iGPU resume because `hypridle`'s `lock_cmd` spawns it as a fresh process that creates a new GPU rendering context right at the resume boundary, a known race trigger (reported on `i915`, not just `xe`). This looked promising enough to test directly: swapped `lock_cmd` to `swaylock` and ran a real `systemctl suspend` under Hyprland. **Result: still hung, no `swaylock` crash this time** — proving the hyprlock crash was a secondary symptom, not the root cause, and reverted back to `hyprlock` since the swap bought nothing but cost the wallpaper blur/clock styling. The compositor-level hang (`hyprctl` IPC timeout) is the real, deeper issue and is independent of which lock screen tool is running — don't re-attempt a lock-screen swap as a fix for this; it's a ruled-out hypothesis, tested and confirmed negative on this exact hardware.
- **Firefox install is unmanaged, its profile is not**: no `ensure_firefox` step and no entry in `packages.txt` — install it however you like. Once present, `linux/setup.sh:link_firefox_profile` symlinks `linux/configs/firefox/user.js` and `chrome/userChrome.css` into the active profile: native-window integration (titlebar merged into tabs, rounded CSD corners matching `decoration.rounding`), compact density, the built-in dark theme, and VAAPI hardware video decode. No forced extensions/policies. `set_firefox_default_zoom` sets 125% default zoom separately, via `content-prefs.sqlite` (the mechanism Firefox's own Zoom UI actually reads — a `user.js` pref like `layout.css.devPixelsPerPx` changes rendering density but never shows up in the Zoom menu, which is a common point of confusion). Needs Firefox fully closed to write safely; skips with a warning otherwise and retries next run.
- **Night light** (`linux/scripts/night-light-toggle.sh`): on Wayland the gamma table resets when the client exits, so gammastep runs as a persistent process while warm is active (the process itself is the state) instead of a one-shot mode.
- **Special-case paths**: `~/.gtkrc-2.0`, `~/.icons/default/index.theme`, and Firefox profile files (dynamic profile path) live outside `~/.config/` and are linked individually rather than via `MANAGED_LINKS`.
- **Theme fonts/cursors**: Fedora has no `fonts-ubuntu` or DMZ-cursor package, so `apply_gsettings_theme` uses `Adwaita Sans` and the `Adwaita` cursor theme (both always present) instead of the old Ubuntu-branded defaults.
- **Monitors**: Hyprland's `hl.monitor({...})` rules in `hyprland.lua` handle hotplug/scale/lid natively; `nwg-displays` (COPR, in `packages.txt`) is the GUI, writing per-monitor overrides to `linux/configs/hypr/monitors.conf` + `workspaces.conf` in plain hyprlang syntax (nwg-displays has no Lua-config awareness). Since Lua has no `source =` equivalent, `hyprland.lua` includes a hand-written interop parser that reads both files and calls `hl.monitor({...})`/`hl.workspace_rule({...})` directly. Both files are versioned, since `~/.config/hypr` is the repo symlink. See `docs/linux-monitors.md`.

### Reference docs

- `docs/bash-primer.md` — repo-specific Bash patterns
- `docs/fish.md` — fish/bash/zsh syntax comparison
- `docs/nvim.md` — Neovim plugin setup and Lazy.nvim usage
- `docs/mise.md` — mise tool management
- `docs/colima.md` — Colima (Docker without Docker Desktop) setup and daily use
- `docs/git-branching-conflicts.md` — Git branching and conflict resolution
- `docs/linux-monitors.md` — monitor hotplug/lid switching, nwg-displays GUI, per-monitor scale
- `docs/tmux-nvim.md` — tmux and Neovim workspace concepts
- `docs/tmux-sessions.md` — tmux session/window/pane workflow and keybindings
