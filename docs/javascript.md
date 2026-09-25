# JavaScript in initd

These scripts use plain JavaScript modules and Node's built-in libraries.
There is no build step or dependency installation. Files ending in `.mjs`
use `import` and `export`; run them with `node path/to/script.mjs`.

## Where to start

Read the small config helpers before the long-running tmux watcher:

1. `shared/lib/json-file.mjs` reads a JSON object, lets a caller change it,
   and writes through a temporary file. Invalid JSON is an error because
   replacing it would lose the user's settings. Config symlinks are preserved.
2. `macos/docker-config.mjs` shows a concrete caller: change two managed
   settings while preserving other keys. `shared/lib/claude-statusline.mjs`
   follows the same pattern for one hook setting.
3. `linux/scripts/audio-ports.mjs` separates parsing from running a command.
   The parser is easy to exercise with an ordinary array in a test.
4. `linux/scripts/docker-menu.mjs` shows `async`/`await`: list containers,
   wait for a selection, then perform the chosen action.
5. The tmux files combine those patterns with caches and a repeating loop.

## File map

| Files | Responsibility |
|---|---|
| `shared/lib/json-file.mjs` | Read and safely update JSON config objects |
| `shared/lib/managed-links.mjs` | Read the Bash symlink manifests without treating paths as shell code |
| `shared/lib/fs.mjs` | Back up paths, install links, and remove only owned links |
| `shared/lib/link.mjs` | Install the selected platform's managed links |
| `shared/lib/cleanup.mjs` | Remove only symlinks pointing at their expected managed source |
| `shared/lib/git-profile.mjs` | Write this machine's Git email while preserving unrelated config |
| `shared/lib/claude-statusline.mjs` | Configure the Claude status-line hook |
| `macos/docker-config.mjs` | Configure Docker credentials and plugin search paths |
| `macos/brewinstall`, `macos/brewinstall.mjs` | Validate a package, update Brewfile, and run Homebrew |
| `linux/scripts/audio-ports.mjs` | Read sound-card port availability |
| `linux/scripts/docker-menu.mjs` | Present container actions through rofi and kitty |
| `linux/scripts/weather-popup.mjs` | Fetch weather and display a notification |
| `linux/scripts/firefox-profile.mjs` | Discover/init a profile, link managed files, and update default zoom transactionally |
| `linux/scripts/config-links.mjs` | Install Linux's special-case config and session-script links |
| `linux/scripts/night-light-toggle.mjs` | Apply the night-light schedule and safely start/stop gamma control |
| `linux/configs/firefox/user.js` | Firefox preferences, loaded by Firefox rather than Node |
| `shared/configs/tmux/.config/tmux/tmux.mjs` | Discover agent sessions, maintain caches, and publish tmux options |
| `shared/configs/tmux/.config/tmux/status-renderer.mjs` | Format status pills, quotas, Git branches, and battery values |
| `shared/configs/tmux/.config/tmux/claude-statusline-hook.mjs` | Pass Claude's stdin JSON to the hook handler |
| `tests/{linux,macos,shared}/*.test.mjs` | Behavior tests grouped by platform and shared scope, using temporary files, command substitutes, and isolated tmux servers |

## Following a tmux update

Start at `main()` at the bottom of `tmux.mjs`. The owning watcher runs
`refresh()` and then the function returned by `createStatusPublisher()`.

`refresh()` identifies each pane's agent through its process ancestry and
open files. `sessionState()` reads complete new log records; `applyEvent()`
updates the model and quota fields. The renderer turns those fields into
text, which is saved in a short-lived pane cache.

The watcher waits one second after each cycle; tmux redraws once per second.
Agent discovery and status publishing share one pane snapshot per cycle;
process and open-file checks stay fresh on every cycle that has an agent.

The publisher reads those caches, combines them with Git and battery values,
and sends changed options to tmux in one command batch. Its returned function
remembers the previous values through a **closure**: local variables survive
between calls without needing a class or global state.

## Efficiency boundaries

Only one watcher per tmux socket performs status work. Idle panes skip agent
process scans and transcript reads. Agent discovery shares one asynchronous
`lsof` call across relevant processes, and transcript reads resume at the last
complete record rather than rereading the whole log each cycle. Git results
are shared per directory for three seconds; battery and naming checks run
every thirty seconds, with creation hooks assigning names and icons sooner.

Records spanning several read chunks retain their byte fragments until a newline
arrives, then concatenate once. This keeps copying proportional to record size
even when a transcript contains large tool output or image payloads.

Setup helpers use synchronous filesystem and subprocess calls where the next
step depends on the previous one. They run on demand, so converting them all
to async would not by itself reduce work. Desktop menu and weather helpers
also run on demand; weather requests and status subprocesses have timeouts.

Large initial transcripts and Codex's SQLite fallback can still make a status
cycle slower. The refresh interval is a delay after work, not a guarantee of
one update every second. Profile a reproducibly slow workload before adding
more caches or concurrency.

## Bootstrap and desktop entry points

`shared/lib/link.sh` is a small launcher. It requests `node@lts` explicitly
through mise, so installation works before the managed mise configuration or
Node exists. Both platform bootstraps install mise before calling it.
`link.mjs`, `cleanup.mjs`, and the Linux config helpers share `fs.mjs`.
Backups preserve broken symlinks and avoid replacing earlier backups.

`linux/setup.sh` calls `config-links.mjs` once before enabling session services,
then `firefox-profile.mjs setup` for profile discovery, linking, and zoom.
Firefox's profile is resolved once per setup call, with no shell-global cache.

The night-light helper accepts `toggle`, `on`, `off`, and `auto`. Its small
`.sh` compatibility launcher supports older installed keybindings; current
Hyprland, Quickshell, and systemd configuration uses the `.mjs` entry point.
Run `linux/setup.sh` on Linux to install the updated session-script links.

## Keeping changes readable

- Use named functions for distinct work and early returns for simple cases.
- Keep short transformations in `map` and `filter`; use a loop or `switch`
  when several branches update state.
- Pass command arguments as arrays. Paths and user input must remain data.
- Let setup errors reach the CLI error handler. A status display may omit
  unavailable data, but should explain intentional fallbacks in a comment.
- Use comments to explain a constraint or decision. Tests capture regressions;
  source comments do not need the full history of earlier implementations.
- Inject the few operations a test must replace, such as `run` or `ask`.
  Keep that interface local to the helper that needs it.

## Checking a change

Syntax-check a file without executing it:

```sh
node --check shared/configs/tmux/.config/tmux/tmux.mjs
```

Run the complete regression suite, including isolated tmux servers:

```sh
INITD_TEST_TMUX=1 node --test tests/linux/*.test.mjs tests/macos/*.test.mjs tests/shared/*.test.mjs
```

The suite requires Node, Bash, Git, Fish, and tmux. Linux desktop commands are
substituted in tests so their error handling can be checked on macOS too;
these checks do not replace a live Linux desktop smoke test.
