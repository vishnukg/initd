# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Full regression suite (includes isolated tmux servers and Linux helper mocks).
# The glob is QUOTED so node expands it recursively: an unquoted tests/*.test.mjs
# matches nothing now that the suite is split by platform, and `node --test` with
# no matching file reports "tests 0" and exits 0 - a green run that ran nothing.
INITD_TEST_TMUX=1 node --test 'tests/**/*.test.mjs'

# Run install behavior tests (auto-detects host OS; uses temporary home directories)
node --test tests/shared/install.test.mjs

# Agent status: process/session isolation, model switches, concurrent writes
node --test tests/shared/agent-*.test.mjs tests/shared/status-publisher.test.mjs tests/shared/watcher-lifecycle.test.mjs tests/shared/enterprise-quota.test.mjs

# Config files bootstrap merges into rather than owns (~/.claude/settings.json,
# ~/.docker/config.json) plus the Firefox profile glue
node --test tests/shared/bootstrap-config.test.mjs

# Fish startup (isolated configuration and mock tools; requires fish and node)
node --test tests/shared/fish-config.test.mjs
# Also test concurrent tmux attachment using a separate temporary server
INITD_TEST_TMUX=1 node --test tests/shared/fish-config.test.mjs

# Syntax-check every script. One `bash -n` call per file, not
# `bash -n file1 file2 ...` - bash -n only ever checks its FIRST argument;
# every filename after that becomes a positional parameter ($1, $2, ...) to
# that first script, never opened at all, so a multi-arg call silently
# "passes" without checking anything past the first file.
for f in bootstrap.sh \
  shared/lib/logging.sh \
  shared/lib/link.sh shared/lib/fonts.sh \
  shared/managed-links.sh \
  macos/bootstrap.sh macos/defaults.sh macos/update.sh macos/managed-links.sh \
  linux/bootstrap.sh linux/setup.sh linux/update.sh linux/managed-links.sh \
  linux/scripts/*.sh; do
  bash -n "$f" && echo "OK   $f" || echo "FAIL $f"
done

# Syntax-check every Node script.
for f in shared/configs/tmux/.config/tmux/*.mjs shared/lib/*.mjs \
  tests/*/*.test.mjs linux/scripts/*.mjs linux/configs/quickshell/*.mjs \
  macos/*.mjs macos/brewinstall; do
  node --check "$f" && echo "OK   $f" || echo "FAIL $f"
done

# Full bootstrap (dispatches by uname)
bash bootstrap.sh

# Re-apply managed symlinks only
shared/lib/link.sh macos    # or: linux

# Sync licensed fonts from the private vishnukg/fonts repo into shared/fonts/
# (needs gh auth; warns and skips otherwise — safe to re-run any time)
shared/lib/fonts.sh

# Set the Git identity (both write this machine's email into local.gitconfig)
node shared/lib/git-profile.mjs personal
node shared/lib/git-profile.mjs work

# Preview / run cleanup
node shared/lib/cleanup.mjs <platform> --dry-run
node shared/lib/cleanup.mjs <platform>

# macOS — add a Homebrew package to the curated Brewfile and install it locally
macos/brewinstall <package>           # auto-detects formula vs cask
macos/brewinstall --cask <package>
macos/brewinstall --formula <package>

# Update tools (per platform)
macos/update.sh
linux/update.sh
```

## Architecture

Runtime code lives in three intentionally decoupled directories: `shared/`, `macos/`, and `linux/`. Tests live in the root `tests/` directory; see `docs/testing.md` for test organization and Arrange/Act/Assert conventions. The contract: `shared/` must not branch on OS; if it would need to, push that branch into the platform script.

```
initd/
├── bootstrap.sh              # ~20-line dispatcher: uname -s → macos|linux
├── tests/                    # behavior tests and isolated integration tests
├── docs/                     # configuration guides and testing conventions
├── shared/                   # cross-platform — sourced by both bootstraps
│   ├── lib/                  # Bash bootstrap helpers plus cleanup.mjs, git-profile.mjs,
│   │                         #   claude-statusline.mjs and json-file.mjs
│   ├── managed-links.sh      # MANAGED_LINKS for shared configs + git helpers
│   ├── configs/              # colima, fish, git, ghostty, kitty, mise, nvim, starship, tmux
│   └── fonts/                # gitignored clone of the PRIVATE vishnukg/fonts repo (Berkeley Mono)
├── macos/                    # self-contained — `rm -rf macos/` and Linux still works
│   ├── bootstrap.sh
│   ├── Brewfile
│   ├── brewinstall            # JavaScript CLI entry; implementation in brewinstall.mjs
│   ├── defaults.sh           # macOS defaults write …
│   ├── docker-config.mjs     # credsStore + brew cli-plugins dir → ~/.docker/config.json
│   ├── managed-links.sh      # appends macOS-only links to MANAGED_LINKS
│   └── update.sh
└── linux/                    # self-contained — `rm -rf linux/` and macOS still works
    ├── bootstrap.sh          # targets Fedora Workstation 44+ (dnf5); some packages come from COPR
    ├── packages.txt          # dnf package list (one per line) — Wayland/Hyprland stack
    ├── setup.sh              # system fixes (fonts, theme/config glue)
    ├── managed-links.sh      # appends the Linux-only links to MANAGED_LINKS
    ├── update.sh
    ├── scripts/              # session scripts invoked by Hyprland/Quickshell, plus
    │                         #   firefox-profile.mjs (a setup.sh helper)
    └── configs/              # hypr, hyprmoncfg, quickshell, rofi, dunst, fontconfig,
                              #   systemd, gtk-3.0, ghostty, firefox, …
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
  ├─ ensure_gh_auth                           # before the fonts sync, so a fresh machine gets fonts in one run
  ├─ shared/lib/fonts.sh                      # clone/pull private fonts repo → shared/fonts/
  ├─ shared/lib/link.sh macos                 # symlinks
  ├─ shared/lib/claude-statusline.mjs         # merges ~/.claude/settings.json's statusLine key → tmux Claude pill
  ├─ ensure_local_fonts                       # COPIES OTFs → ~/Library/Fonts (macOS won't register symlinked fonts)
  ├─ ensure_tmux_terminfo                     # compiles Homebrew ncurses's tmux-256color into ~/.terminfo (system entry lacks Smulx → no nvim undercurl inside tmux)
  ├─ ensure_fish (dscl)
  ├─ mise trust + mise install
  ├─ macos/defaults.sh
  ├─ setup_git_profile (uses shared/lib/git-profile.mjs)
  ├─ ensure_docker_config                 # runs macos/docker-config.mjs: merges credsStore=osxkeychain + brew cliPluginsExtraDirs into ~/.docker/config.json
  └─ ensure_colima_service                # brew services start colima (login autostart)

linux/bootstrap.sh
  ├─ ensure_user_context, ensure_fedora
  ├─ install_packages                          # enables sdegler/hyprland,
  │                                               paolino/hyprmoncfg, and scottames/ghostty COPRs,
  │                                               then dnf-installs
  │                                               packages.txt + the C Development Tools group
  ├─ ensure_gh (official dnf repo), ensure_1password (official dnf repo),
  │  ensure_google_chrome (official dnf repo), ensure_docker (Docker's official
  │  dnf repo), ensure_mise (curl mise.run)
  ├─ ensure_gh_auth                           # before the fonts sync, so a fresh machine gets fonts in one run
  ├─ shared/lib/fonts.sh                      # clone/pull private fonts repo → shared/fonts/
  ├─ shared/lib/link.sh linux                 # symlinks (incl. shared/fonts/berkeley-mono → ~/.local/share/fonts)
  ├─ shared/lib/claude-statusline.mjs         # merges ~/.claude/settings.json's statusLine key → tmux Claude pill
  ├─ linux/setup.sh                           # fonts/theme + config glue
  ├─ ensure_fish (chsh)
  ├─ mise trust + mise install
  └─ setup_git_profile
```

### Script sourcing chain

```
shared/lib/logging.sh           ← must be first; defines log_*, require_command, INITD_* color vars
shared/managed-links.sh         ← MANAGED_LINKS (shared); requires ROOT_DIR
<platform>/managed-links.sh     ← appends to MANAGED_LINKS; requires ROOT_DIR + initial MANAGED_LINKS
```

`ROOT_DIR` must be exported before sourcing `shared/managed-links.sh` because the array embeds absolute paths.

### MANAGED_LINKS — the ownership list

The single array `MANAGED_LINKS` is built in two steps:

1. `shared/managed-links.sh` defines the cross-platform entries (Git, Colima, fish, Ghostty, kitty, mise, Neovim, Starship, tmux, and wallpapers).
2. `<platform>/managed-links.sh` appends OS-only entries (currently nothing on macOS; hypr, hyprmoncfg, quickshell, rofi, dunst, fontconfig, gtk-3.0, the `initd-hyprland-session.service` user unit, the `hyprmoncfgd.service.d` drop-in and the three `night-light*` user units — plus, conditionally, `shared/fonts/berkeley-mono` when present — on Linux). Fonts are deliberately NOT linked on macOS: CoreText refuses to register a font reached through a symlink, so `macos/bootstrap.sh:ensure_local_fonts` copies them instead.

Entry format: `"home path:repo path"`. `shared/lib/managed-links.mjs` reads NUL-separated manifest entries and returns `{ home, source }` objects to the JavaScript installer and cleanup helper.

`~/.gitconfig` is an ordinary `MANAGED_LINKS` entry pointing at the single `shared/configs/git/gitconfig`. That base config carries the name but **no email**, sets `user.useConfigOnly = true`, and `[include]`s `shared/configs/git/local.gitconfig`. Every machine, personal included, gets its email from that file: `shared/lib/git-profile.mjs personal` writes the personal address, `work` prompts for the work one. There is deliberately no fallback — a machine with no `local.gitconfig` refuses to commit (`useConfigOnly`) rather than committing as the wrong identity, and the interactive prompt has no default, so pressing Enter on a work machine picks nothing.

**Adding a managed config:**
- Cross-platform: add to `MANAGED_LINKS` in `shared/managed-links.sh` and place the source under `shared/configs/<name>/`.
- Platform-only: append to `MANAGED_LINKS` in `<platform>/managed-links.sh` and place the source under `<platform>/configs/<name>/`.

Then add a corresponding assertion in `tests/install.test.mjs` (or rely on the generic managed-links loop, which iterates over whatever the host platform produces).

### Machine-local secrets

These paths are gitignored and never committed:

| Path | Purpose |
|---|---|
| `shared/configs/git/local.gitconfig` | This machine's Git email (personal or work); git refuses to commit without it |
| `shared/configs/fish/.config/fish/local.env.fish` | Machine-specific environment variables, loaded by every Fish shell before tmux auto-attach |
| `shared/configs/fish/.config/fish/local.fish` | Interactive-only aliases and preferences |
| `shared/fonts/` | Clone of the PRIVATE `vishnukg/fonts` repo (Berkeley Mono — paid, per-user licensed; this repo is public, so committing the OTFs would redistribute them). Synced by `shared/lib/fonts.sh`, which warns-and-skips without `gh` auth |

All follow the same pattern: used at startup/bootstrap if present, silently skipped if absent.

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

`backupPath` in `shared/lib/fs.mjs` moves any pre-existing unmanaged file to `${BACKUP_ROOT}/<relative-path>` before taking ownership. `BACKUP_ROOT` is exported by each platform's `bootstrap.sh` so re-applying links uses the same timestamped folder for the whole run.

### Plain .mjs, no toolchain

Every Node script here is `.mjs` with no build step, no `package.json`, and no `node_modules` — `node --check` is the whole syntax check and `node --test` the whole test runner. Files are run straight out of the repo through the `MANAGED_LINKS` symlinks (`node ~/.config/tmux/tmux.mjs watch`, `#!/usr/bin/env node` on `claude-statusline-hook.mjs`), so editing one is the deploy.

**There is no `python3` anywhere in the bootstrap path, and it should stay that way.** Four steps used to shell out to embedded python heredocs — the two JSON merges (`~/.claude/settings.json`, `~/.docker/config.json`), Firefox's `profiles.ini` parse, and the `content-prefs.sqlite` zoom write — which made python an undeclared runtime dependency of a repo that otherwise needs only bash, node and mise. All four are `.mjs` now: `shared/lib/json-file.mjs` holds the merge-don't-own invariant for both JSON callers, and `linux/scripts/firefox-profile.mjs` does the INI parse by hand and the sqlite write through `node:sqlite`. Anything new that needs to parse or edit structured data belongs in a tested `.mjs`, not in a heredoc.

The `shared/lib/link.sh` launcher uses **`mise exec node@lts -- node <script>`** because it runs before the managed mise configuration exists. Both bootstraps install mise first. Both bootstraps and `linux/setup.sh` reach node the same way (their `run_node` helpers), never a bare `node` and never a bare `mise exec -- node`: once `~/.config/mise` is linked, an exec with no tool named installs *every* missing tool in the global config first, which would turn the statusLine step into a silent full toolchain install that aborts bootstrap if any one tool fails. `node` comes only from mise (`node = "lts"` in the mise config; it is in neither the Brewfile nor `packages.txt`), so on a fresh machine there is no node on `PATH` until `mise install --yes` — and `linux/setup.sh` and the statusLine step both run before that. `mise exec` installs a missing tool on demand, and sends its install progress to stderr, so it works at any point in the sequence and a `$(...)` capture of the script's stdout stays clean.

This was briefly TypeScript, run through Node 24's type stripping. It got reverted, and the reasoning is worth keeping so it isn't re-litigated: of the three bugs that actually shipped in `createStatusPublisher`, `tsc` caught exactly one (`pill` used but never imported) and any linter's `no-undef` catches that same one. The two that needed real finding — a missing `set-option` verb, and a doubled cache read whose fallback lacked the try/catch of the call above it — were invisible to it. **The test caught those, and the test is what earned its keep.** Against one linter-grade catch, TypeScript wanted a `node_modules`, a Node ≥22.18 floor, ~30 non-null assertions, and a handful of `x === undefined` guards that are dead at runtime because `Number.isFinite(undefined)` is already false. It also added a silent failure mode this repo did not have: a non-erasable construct (an `enum`, say) throws at load, `main()` swallows it, and the status line just goes blank.

What survived the revert, because it was never really about types: `findAgent` takes any row carrying `pid`/`parent`/`agent`, and the process/transcript state shapes are described at the top of `tmux.mjs`. `applyEvent` handles external event formats; `status-renderer.mjs` formats models and quotas. See `docs/javascript.md` for a reading guide.

If typing ever seems worth revisiting: the bar is a bug class the tests genuinely cannot reach, and JSDoc with `checkJs` gets most of the way there without changing what runs.

### Line endings

`.gitattributes` enforces `eol=lf` for `*.sh`, `*.fish`, `*.conf`, `*.ini`, and other text files so commits from any host (including Windows) land as LF — the only line-ending bash and `/etc/`-style configs can parse on macOS or Linux.

### Linux-specific quirks

The Linux desktop is **Wayland-only**: Hyprland installed alongside Fedora's stock GNOME (both offered at the GDM login screen). Fedora's own repos don't carry the Hyprland ecosystem, `hyprmoncfg`, or `ghostty` — `install_packages()` enables their three COPRs first (`sdegler/hyprland`, `paolino/hyprmoncfg`, `scottames/ghostty`) before resolving `packages.txt`. The old X11 stack (i3, polybar, picom, xsettingsd, autorandr, Xresources) and the previous Ubuntu-specific fixes (Intel WiFi/Bluetooth udev rules, WiFi regdomain, power-profile AC/battery auto-switch, Chrome apt-arch pin) have been removed from the repo; git history has them if ever needed. This machine is different hardware from the old Ubuntu laptop those fixes targeted, and the trimmed-down setup intentionally doesn't try to guess replacements — add back only what a given machine actually needs.

- **Hyprland config** (`linux/configs/hypr/hyprland.lua`): Hyprland's Lua config format (hyprlang `.conf` support is removed entirely in Hyprland 0.57; this repo ported fully rather than keep a config format on a deprecation countdown). Per-monitor scale (1.33333x on the laptop panel and on unmatched outputs — a 1920x1200 logical workspace on the 2560x1600 panel) via `hl.monitor({...})`, with generated profile rules loaded from `hyprmoncfg-monitors.lua` by the guarded loader hyprmoncfg itself maintains on the last line; built-in blur/rounding/animations; `kb_options = ctrl:nocaps` and `repeat_delay/rate` for input. The polkit auth agent is `lxpolkit` (Fedora has neither `polkit-gnome` nor a `hyprpolkitagent` package). Hyprland only detects `hyprland.lua` vs `hyprland.conf` at compositor **startup**, not on `hyprctl reload` — use `Hyprland --verify-config --config <path>` to validate changes without restarting. **Every dispatch payload is Lua too**, over `hyprctl` and over the IPC socket alike: `hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })'`, not `hyprctl dispatch workspace 2`. Quickshell's convenience wrappers (`HyprlandWorkspace.activate()`) still emit the legacy syntax and fail with a log warning rather than an error, so the bar sends Lua strings through `Hyprland.dispatch()` instead.
- **There is no Ghostty terminal server, and no systemd setup for Ghostty at all.** It used to run one — Fedora's `app-com.mitchellh.ghostty.service` plus a drop-in carrying `--gtk-single-instance --quit-after-last-window-closed=false --background-opacity=0.92` — so `$mod+Return` asked a resident process for a window (~250ms) instead of cold-starting one (574ms). Two measurements retired it. kitty opens a fresh process in **0.24s**, beating the server's **0.62s** with no daemon at all; and the server was where Ghostty's leak compounded, going 69 → 204 MB across ~5 window open/close cycles and holding that with **zero windows open**. The unit is Fedora's, ships disabled, and nothing in this repo enables it, so a fresh bootstrap needs no action — the drop-in, its `MANAGED_LINKS` entry and the `enable_ghostty_server`/`disable_ghostty_server` step are all gone. One thing worth remembering if a server is ever wanted again: **a single-instance client forwards only the request, so config flags passed to it are silently dropped** (`--background-opacity`, `--title`, `--class` all no-op) — which is why that opacity had to live on the *server* command line. The `$mod+SHIFT+ALT+Return` Ghostty fallback bind deliberately omits `--gtk-single-instance` for the same reason the server is gone: that flag would make the first window the instance owner for every later one, reinstating the shared-process accumulation.
- **kitty is the default terminal; Ghostty is kept installed as the fallback.** `$mod+Return` opens kitty, `$mod+SHIFT+ALT+Return` opens Ghostty, and `linux/scripts/docker-menu.mjs` shells out with `kitty`. Ghostty held the default for a stretch, and the memory benchmark is what took it back: Ghostty 1.3.1 leaks on **window lifecycle**, not throughput — a synthetic 120k-line unicode burst (the trigger in upstream #10244) moved it 204 → 204 MB, while opening and closing ~5 windows took it 69 → 204 MB and it held that with zero windows open, matching #9433 rather than #10244. Over a day of real use it reached 1068 MB with 964 MB of private dirty heap against a 10 MB `scrollback-limit`, so scrollback never explained it. Upstream also tracks #9786 (Ghostty + Claude Code specifically) and #10269 (still leaking on 1.3.0-main after a PageList fix); kitty's fresh window peaked at 162 MB on the same payload and returned all of it on exit. Cold start agrees — kitty ~223ms against Ghostty's ~680ms, which nothing tunes (see below). That is exactly why **neither terminal is launched single-instance, and why no Ghostty server is enabled**: one process owning every window is what makes the leak permanent, while separate processes hand the memory back on close — the same reasoning that retired the server above. kitty gets no `--single-instance` and the Ghostty fallback no `--gtk-single-instance`. `shared/configs/kitty/.config/kitty/kitty.conf` mirrors the Ghostty config on everything except the font block (VSCode Dark palette; note ligatures differ too — kitty runs them ON via `features="+liga +calt"` plus `disable_ligatures never`, since Berkeley's GSUB carries `calt`, while Ghostty pins `font-feature = -calt`/`-liga` off), and **neither config has split or tab bindings** — tmux owns that layer and its panes survive the terminal dying, which terminal-native splits do not. The Linux-only 0.92 opacity is a config file, *not* a launch flag: a flag only reaches windows opened by that one keybind, leaving rofi, `docker-menu.sh` and `.desktop` launches at the macOS value (0.58 for both terminals, deliberately aligned). **The two terminals solve it differently, because only kitty has a per-OS include.** kitty expands `${KITTY_OS}` in include paths, so `include ${KITTY_OS}.conf` — deliberately the **last** line of `kitty.conf`, since later values win — pulls in a committed `linux.conf` carrying `background_opacity 0.92` alongside `hide_window_decorations titlebar-only`. That file is tracked: the value is a Linux one, not a per-machine one. Ghostty has no such mechanism — `config-file` does no variable expansion, only repetition, relative paths and a `?` prefix for optional includes — and its single config is symlinked to both platforms. So the *platform script places the file* rather than the include selecting it: `linux/setup.sh:link_ghostty_linux_conf` symlinks the tracked `linux/configs/ghostty/linux.conf` (carrying `background-opacity = 0.92`) next to the shared config, which ends with `config-file = ?linux.conf`. The `?` makes it optional, so on macOS — where nothing creates that link — it is a no-op. The symlink itself is gitignored; the content it points at is tracked, under `linux/` like every other platform config. **Most of Ghostty's OS-specific settings need none of this**: `macos-*` and `gtk-*` options are silently inert on the wrong platform (`ghostty +validate-config` on Fedora accepts the `macos-*` lines with zero warnings), so they live in the shared config. Only `background-opacity`, which differs by *value* rather than by key, has to be split out — which is why that file has exactly one setting in it. Note the ordering trap on the kitty side: `include ${KITTY_OS}.conf` used to sit above the background block, where the shared `background_opacity` overwrote anything `linux.conf` set; that is why the 0.92 previously needed a `globinclude local.conf` at the very bottom. The Ghostty config also pins `gtk-single-instance = false`, so a flagless launch (the fallback keybind, any script) always gets its own process rather than trusting Ghostty's `detect` default — but **that does not reach rofi or `.desktop` launches**: Fedora's packaged entry carries `Exec=ghostty --gtk-single-instance=true`, an explicit CLI flag beats the config file (measured — two launches share one pid with the flag, separate pids without), so those still join one long-lived server that nothing reaps. The leak is current on 1.3.1-4.fc44: ~10 MB per window open/close, 231 MB held with zero windows open, and the default `quit-after-last-window-closed = true` does not fire in single-instance mode. Fixing the launcher path means shadowing the desktop entry in `~/.local/share/applications`, deliberately not done — it costs those launches ~270ms → ~680ms and needs re-checking on package updates. Cold start itself is not tunable: renderer (`GSK_RENDERER` ngl/gl/vulkan), font, `GTK_A11Y`, shell-integration and even `--config-default-files=false` all measure 640–690ms, against kitty's 223ms and a single-instance client's 274ms. **The two terminals deliberately run different fonts.** kitty is on **Berkeley Mono Regular, size 16** (paid, per-user licensed — PRIVATE `vishnukg/fonts` repo, synced into gitignored `shared/fonts/` by `shared/lib/fonts.sh`; macOS copies the OTFs via `ensure_local_fonts`, Linux links them into `~/.local/share/fonts`); Ghostty is on **FiraCode Nerd Font, `font-style = Retina` (450), size 15** — though whether that weight actually resolves is **unconfirmed**: Fira Code's weights are not RIBBI-paired (`FiraCodeNerdFont-Retina.ttf` is ID1 `FiraCode Nerd Font Ret` / subfamily `Regular`, with only the typographic names saying `Retina`), `ghostty +list-fonts` reports the styles abbreviated as `Reg`/`Ret`/`Med`/`SemBd`, and `+show-face` prints the typographic family — identical for every weight — so the CLI cannot tell Retina from Regular. Ghostty has no `postscript_name` escape hatch either (measured: `font-family = "FiraCodeNF-Ret"` falls back like a nonexistent family). See the comment in the Ghostty config for the fallbacks if it renders too light. That is not drift, it is forced: kitty's CoreText backend silently rejects patched Nerd Font builds as text fonts and falls back to Menlo, whereas Ghostty's font stack has no such check — so only Ghostty can run the patched build. Berkeley in turn resolves cleanly on **both of kitty's** backends, so kitty's font block lives once in the shared `kitty.conf` and `macos.conf` carries no font override at all. Berkeley originally arrived replacing FiraCode Nerd Font Medium 15; the weight and size history since is in `7b2a645`/`ed870ae`/`fe0e372`. Two things are load-bearing and both fail *silently*:
    - **Faces are addressed by `postscript_name=`, not `family=`/`style=`.** The oblique faces are not RIBBI-paired — `BerkeleyMono-Oblique.otf` sets name ID 1 to "Berkeley Mono Oblique" with subfamily "Regular", and only the typographic names (16/17) say "Berkeley Mono" / "Oblique". fontconfig merges both so `style="Oblique"` matches on Linux, but CoreText keys off name ID 1, so on macOS the family holds only Regular and Bold and the italic lines would find no such style. Note the PostScript names contract `Bold-Oblique` to `BoldOblique` — they do **not** match the filenames.
    - **`linux/configs/fontconfig/fonts.conf` forces the family to `spacing=100` at scan time.** Only `BerkeleyMono-Regular.otf` stores its advance widths in the compressed `hmtx` form (`numberOfHMetrics=1`); every other face carries per-glyph metrics where a handful of glyphs out of 645 deviate from the 600-unit width, so fontconfig concludes "not monospace" and leaves spacing unset. kitty's fontconfig backend queries `:spacing=100` for text faces, so bold/italic/bold-italic resolved to FiraCode while Regular rendered correctly. This rule is required **in addition to** the `postscript_name=` descriptors — without it the faces are invisible to fontconfig matching no matter how they are addressed.

    Berkeley carries **no Nerd Font icon glyphs**, so kitty's `symbol_map` sends the Private Use Area to the standalone non-Mono **Symbols Nerd Font**. Ghostty no longer needs that fallback — its patched FiraCode build carries the icons in-family (verified: `U+E7C5` resolves straight to FiraCode Nerd Font) — but the font stays installed because kitty still depends on it. That font is installed by the `font-symbols-only-nerd-font` cask on macOS and by `linux/setup.sh:install_symbols_nerd_font` on Linux (Fedora packages no equivalent, and its absence is a *silent* icon-width shift onto kitty's built-in sprites or FiraCode — not an error). Powerline separators are unaffected either way: Ghostty draws `U+E0B0`–`U+E0D4` with internal sprites, so tmux's status line stays cell-aligned regardless of font. FiraCode Nerd Font is installed on both platforms, is Ghostty's text font, and remains fontconfig's generic `monospace` preference for GTK apps. Verify resolved faces with `ghostty +show-face --string=Ag [--style=italic]` and `kitty --debug-font-fallback`. **A patched build has since returned — in Ghostty, not kitty**, which is exactly why kitty's restriction still matters: kitty's CoreText backend silently rejects non-Mono patched Nerd Fonts as text fonts (their double-width icon glyphs fail its monospace validation) and falls back to Menlo, and `family=`/`style=` matching against Fira Code's non-RIBBI weights resolves every style to Light — which is why `macos.conf` had to pin `postscript_name=FiraCode-Retina` back when kitty ran that build. Ghostty needs none of that and names the face plainly as `font-family = "FiraCode Nerd Font"` + `font-style = Retina`. Move kitty onto a patched build again and the pin has to come back. Full history in commits `ca7fd1b`/`94986b9`/`8615032`/`ed870ae`. **Two latency knobs are set in the shared kitty.conf and are safe on both platforms**: `repaint_delay 8` (the default 10 ms sits above a 120 Hz panel's 8.33 ms frame, so it — not vsync — was the limiter and kitty rendered ~60 FPS; below the frame time vsync governs, so it is 120 FPS on the laptop and a no-op on a 60 Hz display) and `wayland_enable_ime no` (kitty's docs call the Wayland IME path latency-adding; no IME is used; inert on macOS — kitty's option table has no platform conditionals, which is the same reason the `macos_*` lines are inert on Linux). `sync_to_monitor` and `input_delay` are deliberately left at defaults: Hyprland composites with tearing off so unsynced frames would just be dropped, and a lower input_delay risks the full-screen redraw flicker kitty warns about in tmux/nvim. Cold start (~180 ms) is kitty's own and is measured identical with the full config, with the config watcher off, and with `--config NONE`. **Note the SUPER binds in both terminal configs are macOS-only in practice** — Hyprland claims `SUPER+h/j/k/l`, `SUPER+1..9` and `SUPER+Return` first, so they never reach the terminal on Linux.
- **Companion stack**: Quickshell (`shell.qml`) provides the Hyprland bar, Wi-Fi/Bluetooth status, system tray, audio, battery, metrics, weather, and Docker status; rofi 2.0 (`config.rasi`), dunst (`dunstrc`), hyprlock + hypridle, hyprpaper (wallpapers committed at `shared/wallpaper/`, linked to `~/.local/share/wallpapers`), grim/slurp, wl-clipboard.
- **Weather icons**: the bar asks wttr.in for `%C|%t|%S|%s` — condition *name*, not `%c`'s colour emoji — and `weatherIcon()` maps that name to a Nerd Font `nf-md-weather-*` glyph, so weather looks like every other bar icon. The keyword tests run in severity order (thunder → ice → fog → sleet/freezing → snow → rain → cloud → clear); order matters, e.g. fog is checked before "freezing" so "Freezing fog" isn't drawn as sleet. `%S`/`%s` (sunrise/sunset) pick the sun-vs-moon variant for clear and partly-cloudy skies.
- **Bar logic lives in `linux/configs/quickshell/bar-logic.mjs`**, not in the QML. The ordering-sensitive pure functions — `weatherIcon`, `weatherColor`, `weatherCelsius`, `loadColor`, `clockMinutes`/`isNight`, and `deviceKind`/`kindRank` — are an ES module that `shell.qml` and `AudioMenu.qml` import (`import "bar-logic.mjs" as BarLogic`), so `tests/linux/bar-logic.test.mjs` can cover them under `node --test` while the QML keeps only the thin wrappers that read its own properties. Glyphs are `\u{...}` escapes there for the same reason as in `status-renderer.mjs`: they are Private Use Area code points that editors and terminals silently drop.
- **Bar colour**: `BarItem` has a single `foreground`, so colour is per item, not per glyph — icon and number always match. Colour means *state*, never decoration: `weatherColor()` is a temperature ramp that stays flat through the mild band (12–25 °C), deepens through blue below 12 °C and through amber to red above 25 °C, reading the unit off the string so a °F reading converts first, `loadColor()` ramps CPU and memory neutral → amber at 70% → red at 90%, and battery, power profile and audio-mute keep their own. Docker, brightness and the clock are deliberately flat `#e8eaf0` — a count and a backlight level have no severity to signal.
- **Bar interaction model** (`BarItem.qml`): hovering an item shows a `BarTooltip` label below it — title plus current reading — and clicking is reserved for items that *do* something: the power-profile icon cycles power-saver/balanced/performance, the night-light bulb toggles gammastep (outlined bulb off, lit amber bulb while warm), Docker opens the rofi container menu, weather fires the wttr.in notification, audio opens `AudioMenu`. CPU, memory, brightness, and battery are hover-only. Tray items (Wi-Fi via nm-applet, Bluetooth via blueman) still open `TrayMenu`, the monitor icon opens `DisplayMenu`, and the clock still opens `CalendarPopup` on click — dropdowns are for menus, tooltips are for readouts. Audio is the one item with a right-click too (`secondaryClickable`/`onSecondaryClicked` on `BarItem`): its left-click had to be handed to the device picker, so one-click mute moved to the right button rather than disappearing.
- **Audio device picker** (`AudioMenu.qml`, rows via `MenuRow.qml`): left-clicking the audio item opens a popup listing every PipeWire output and input endpoint; clicking one writes `Pipewire.preferredDefaultAudioSink`/`preferredDefaultAudioSource`, which is the *configured* default WirePlumber persists to `~/.local/state/wireplumber/default-nodes` — not a session-only override. `endpoints()` filters `Pipewire.nodes` by the composite `PwNodeType.AudioSink`/`AudioSource` flags and drops `isStream` nodes, so per-application streams and the output half of a filter chain stay out of the list. Devices are classified by **node name**, not `properties`: `properties` is only populated for nodes bound by a `PwObjectTracker` and this list deliberately binds none of them, whereas `name`/`nickname`/`description`/`isSink`/`type` are constant and readable unbound. The `deviceKind()` tests run in a fixed order because HDMI and USB endpoints are ALSA devices too — they must be matched before the generic `alsa_` test claims them as `Built-in`. Rows are grouped Built-in → USB → HDMI → Bluetooth → AirPlay → Virtual, so the laptop's own speaker and mic keep a stable position regardless of what is plugged in. Labels prefer the attached display's own name over `node.nickname` ("Speaker", "HDMI 1"), which in turn beats `description` (it repeats the sound card name); the kind tag on the right is what disambiguates two devices that both call themselves "Speaker". **Neither the display name nor the "is anything plugged in?" answer comes from PipeWire's node properties** — both hang off the sound card's *port* (`device.product.name`, lifted from the monitor's ELD, and the port's availability), and Quickshell's Pipewire service exposes nodes only, no devices and no routes. `linux/scripts/audio-ports.mjs` reads `pactl --format=json list cards` and emits a JSON map of attachment state and display name, which `portProcess` reads as an ALSA-port map joined to an endpoint by the port token its name embeds between double underscores (`...HiFi__HDMI1__sink`). Empty ports are filtered out of both lists, so an unused HDMI socket is not a dead row you can select. Two rules keep that from hiding something real: only an explicit `not available` counts as empty (a port that cannot detect presence reports `availability unknown`, and the built-in speaker and mic report exactly that), and every lookup fails open — an endpoint the map says nothing about, which is every Bluetooth, AirPlay, and filter-chain node, is always shown and never renamed. Duplicate port tokens across cards are omitted so lookups fail open instead of borrowing another card's state. The current default is kept in the list even if its port reads empty, so the checkmark always has somewhere to sit; in practice WirePlumber refuses to make an unavailable sink the default at all, so that guard is only covering the window where the map is stale. The script re-runs on every menu open rather than on a PipeWire signal, because plugging a monitor in or out does not change the sink set at all — all three HDMI sinks exist whether or not anything is attached.
- **Display profile switcher** (`DisplayMenu.qml`, rows via `MenuRow.qml`): the monitor item opens a popup with a read-only **Displays** section (one row per output: `2560x1600 · 120 Hz · 1.33x`) over a clickable **Profiles** section that runs `hyprmoncfg apply <name>`. All of it comes from a single `hyprmoncfg status --json` call — profiles with `active`/`recommended`, monitors with mode/scale/make/model/`internal`, and daemon state — so unlike the audio menu there is no helper script to parse anything. **`apply` must be passed `--confirm-timeout 0`**: it otherwise prompts `Keep this configuration? [y/N]`, and with no tty on the other end it reads EOF, *reverts the profile*, and exits 1. That gives up the revert-on-timeout safety net, which is the right trade here only because every profile in the list was saved from a layout that already worked. hyprmoncfg validates before it commits and refuses what it cannot lay out (a profile saved against a different external monitor typically fails `layout overlaps: DP-1 intersects eDP-1`), and since the popup has already closed by then, the first stderr line is surfaced through `notify-send` or the reason would be lost entirely. The switcher only *picks* between saved profiles — creating and arranging them stays a `hyprmoncfg tui` job, because the CLI's `save` only snapshots the current state and there is no command to set a monitor's mode. Going around it with `hyprctl keyword monitor` is not an option: the daemon owns the generated `hyprmoncfg-monitors.lua` and reasserts the layout on every monitor event.
- **Current idle/suspend/lid behavior**: hypridle locks the session after 10 min idle and turns the display off 30 s later (lock first, so hyprlock is already drawn when the screen wakes; the old i3 setup only went dark). systemd-logind uses its default lid-close suspend policy. Hypridle also requests a session lock through `loginctl` before sleep, which invokes `hyprlock`, then waits for Hyprland's session-lock confirmation (`inhibit_sleep = 3`) before releasing its delay inhibitor. `hyprmoncfgd` selects and applies monitor profiles for hotplug and lid events.
- **System fixes** that need sudo: `video` group membership (backlight is `root:video`; required for the XF86MonBrightness keybinds — takes effect after re-login) and disabling idle daemons this machine gets nothing from (`disable_unused_daemons`: `ModemManager` — no modem on this hardware; Fedora's `abrt*` crash reporter — ~57 MB resident, only useful for filing Fedora bug reports; `rsyslog` — ~28 MB to duplicate the journal into `/var/log/messages`). These are applied by `linux/setup.sh`, which also does several non-sudo fixes: it masks the `hypridle`/`hyprpaper` **user units** (their upstream units bind to `graphical-session.target`, so they would also start inside GNOME — where hyprpaper segfaults — and race the `hl.on("hyprland.start", ...)` autostart block that this repo uses instead), wires `hyprmoncfgd` to `graphical-session.target` instead of its packaged `default.target` (a managed drop-in adds `ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland`, so it starts only once Hyprland is up and the env is imported — its first apply used to fail with an empty `hyprctl instances` and wait for a poll — and never under GNOME). The one-way migrations off Waybar and the old X11 clamshell script, and CopyQ (dropped for its ~120 MB clipboard-history server + monitor footprint; unused), have been removed now that they are complete — git history has them.

- **Session target shim** (`linux/configs/systemd/user/initd-hyprland-session.service`): a `Type=oneshot`/`RemainAfterExit=yes` unit running `/usr/bin/true`, started from the `hyprland.start` autostart block after `dbus-update-activation-environment` and `systemctl --user import-environment`. It exists purely so `graphical-session.target` is reached under Hyprland the way it is under GNOME — user services that key off that target (and the portals) would otherwise never come up in this session. It is a managed link like any other config, not something bootstrap enables.

- **Speaker audio**: nothing in bootstrap touches it. The XPS 13 DX13260 sidecar-amp quirk (`options snd_soc_sof_sdw quirk=65536`) is upstream from Linux 7.2 and its setup.sh step was removed in `4546274`; the SOF speaker DRC is left at its default (`dfbaa62`). Git history has both, plus the old codec-only filter-chain EQ. If the speakers ever want voicing, tune it by ear (EasyEffects is installed) and bake the result into a PipeWire filter chain; `AudioMenu.qml` already filters filter-chain nodes out of the picker.
- **Firefox install is unmanaged, its profile is not**: no `ensure_firefox` step and no entry in `packages.txt` — install it however you like. Once present, `linux/scripts/firefox-profile.mjs setup` symlinks `linux/configs/firefox/user.js`, `chrome/userChrome.css`, and `chrome/userContent.css` into the active profile: native-window integration (titlebar merged into tabs, rounded CSD corners matching `decoration.rounding`), normal density, the built-in dark theme, and VAAPI hardware video decode. No forced extensions/policies. `setDefaultZoom` sets 133% default zoom separately, via `content-prefs.sqlite` (the mechanism Firefox's own Zoom UI actually reads — a `user.js` pref like `layout.css.devPixelsPerPx` changes rendering density but never shows up in the Zoom menu, which is a common point of confusion). Needs Firefox fully closed to write safely; skips with a warning otherwise and retries next run.
- **Night light** (`linux/scripts/night-light-toggle.mjs`, units under `linux/configs/systemd/user/night-light*`): on Wayland the gamma table resets when the client exits, so gammastep has to stay running while warm is active. It runs as the `night-light.service` user unit (constant 4500 K), and *the unit being active is the state* — no state file. The script has four modes: `toggle` (the `$mod+SHIFT+n` keybind and the bar's bulb item), `on`/`off`, and `auto`, which applies the schedule — warm from 19:00 to 07:00 — and is idempotent. `night-light-schedule.timer` fires `auto` at both boundaries (`Persistent=true`, so a boundary slept through fires on wake), and `night-light-schedule.service` is also `WantedBy=graphical-session.target`, so a login inside the warm window comes up warm with no hyprland.lua change; `linux/setup.sh:enable_night_light_schedule` enables both. A manual toggle between boundaries stands until the next one. `night-light.service` carries `ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland` because gammastep needs wlr-gamma-control, which GNOME lacks — under GNOME every start is silently skipped, which is why the script checks `is-active` after starting rather than trusting the exit status before it notifies. Every path ends with `qs ipc call bar refreshNightLight`, and `nightLightStateProcess` in `shell.qml` just runs `pgrep -x gammastep`, on that call and on the 30s timer. Stopping takes ~4 s because gammastep fades the gamma back before exiting; `systemctl stop` waits for that, so the bar ping always sees the process gone. **Two gammasteps must never coexist**: Hyprland refuses a second gamma controller for an output, which is correct, but 0.56.2 then leaks the refused entry (`CGammaControl`'s early `sendFailed()` returns happen before the destroy hooks are set, and `good()` only checks the resource exists), so every later controller for that output is refused until Hyprland restarts — the symptom is gammastep logging `1/1 output(s) do not support gamma adjustment` every 5 s and the screen not changing while the bar and notifications disagree. The unit's `ExecStartPre=-pkill -x gammastep` and the script's `stopStrays` (which waits for strays to exit and refuses a second controller on timeout) keep that path unreachable; if it ever happens anyway, only a log out/in clears it. `NIGHT_LIGHT_HOUR` overrides the clock for testing `auto`. gammastep was kept over `hyprsunset` (available in the sdegler COPR) because nothing runs while the light is off, which matches how the rest of this setup treats background processes.
- **Special-case paths**: `~/.gtkrc-2.0`, `~/.icons/default/index.theme`, and Firefox profile files (dynamic profile path) live outside `~/.config/` and are linked individually rather than via `MANAGED_LINKS`.
- **Theme fonts/cursors**: Fedora has no `fonts-ubuntu` or DMZ-cursor package, so `apply_gsettings_theme` uses Inter (`Inter 11` UI / `Inter 12` document, from the `rsms-inter-fonts` package) with `FiraCode Nerd Font 11` for monospace, and the always-present `Adwaita` cursor theme instead of the old Ubuntu-branded defaults. Cursor size is 24, kept in sync with `hl.env("XCURSOR_SIZE", ...)` in `hyprland.lua` — the gsetting only reaches GTK apps, the env var is what Hyprland itself draws. `apply_gsettings_keyboard` likewise mirrors `ctrl:nocaps` and the key-repeat rate into GNOME so both sessions feel the same.
- **Monitors**: `hyprmoncfg` owns monitor profiles, workspace assignments, hotplug, and lid changes. Its generated `hyprmoncfg-monitors.lua` is loaded by a guarded `dofile` that hyprmoncfg 1.17+ writes and maintains itself at the end of `hyprland.lua` (after everything else, so nothing can override the applied layout; it tolerates the file not existing yet); profiles are versioned under `linux/configs/hyprmoncfg/`. See `docs/linux-monitors.md`.

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
