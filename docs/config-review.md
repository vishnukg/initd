# initd configuration review — 2026-09-12

The available automated checks pass on the Mac after the fixes below. The
review covers the JavaScript helpers, bootstrap/update/link/cleanup paths,
terminal and shell configuration, Neovim, and the Linux desktop configuration.
It is not a claim that every Linux service or hardware feature has been run:
Hyprland, Quickshell, systemd, and the laptop hardware are unavailable here.

| Verification | Result |
| --- | --- |
| Full regression suite, including tmux integration | 101 passed; none skipped in the full JavaScript/Mac review |
| JavaScript syntax | All 27 tracked Node scripts/entry points and Firefox's `user.js` passed in the follow-up |
| JavaScript correctness lint | All 28 tracked JavaScript files/entry points passed in the full review |
| Shell syntax | All 14 tracked shell files and 2 tracked Fish files passed in the follow-up |
| Lua syntax | 38 files passed |
| JSON syntax | 8 files passed |
| Mise and Starship TOML | Taplo passed |
| Colima YAML, fontconfig XML, Brewfile Ruby | Parsers passed |
| Kitty and Ghostty configuration | Native validators passed |
| tmux configuration | Parse-only validation passed |
| Neovim | Startup and loading all 39 installed plugin configurations passed |
| Managed macOS symlinks | All 10 resolve to the expected source |
| macOS and Linux symlink install/cleanup | Isolated-home tests passed |
| Homebrew dependencies | Brewfile check passed with normal cache access |
| Mise tools | All 54 configured tools report installed |

The JavaScript lint checked undefined names, unreachable code, duplicate keys
and arguments, invalid typeof comparisons, constructor/super errors, and
constant conditions outside intentional loops. It used the already-installed
ESLint library; no project dependencies or build step were added.

The initial review's native application and non-script parser results are
retained above. The full JavaScript/Mac follow-up below lists which live checks
were rerun; it did not rerun the Lua/JSON/YAML/XML/Ruby parsers or Kitty validator.

**Corrections made during the review**

- Reusing a backup directory preserves existing backup files, directories, and
  broken symlinks by choosing an unused numbered suffix. A regression test
  verifies that every previous copy survives.
- Bootstrap, setup, and update commands run mise tool operations with the initd
  repository as their working directory. Launching these scripts from another
  project no longer selects that project's tool configuration. This follows
  mise's [directory-based configuration precedence](https://mise.jdx.dev/configuration.html).
  The Firefox helper test also checks the directory argument from another cwd.
- Git profile selection now removes the work email override when explicitly
  switching to personal, while retaining unrelated local settings. An
  unattended invocation with no selection preserves the existing identity.
  Tests use temporary files, including the previously live-path personal test.
- JSON config merges reject arrays, null, and primitive roots without rewriting
  them. Temporary files use unique names and exclusive creation with private
  permissions.
- Firefox zoom timestamps now use seconds, matching Mozilla's
  [ContentPrefService2 implementation](https://raw.githubusercontent.com/mozilla-firefox/firefox/main/toolkit/components/contentprefs/ContentPrefService2.sys.mjs).
  Earlier code and its test incorrectly used microseconds.
- Firefox config linking backs up existing user files. Fresh-profile progress
  messages go to stderr so they cannot become part of the captured profile path.
- Hyprland exports mise shims and the local binary directory before launching
  desktop applications, making Node helpers available without starting fish.
- Docker menu failures are reported instead of being treated as empty output
  or successful operations. Rofi selections must come from the container list;
  missing executables and cancelled menus are handled.
- Weather notification and IPC subprocesses handle asynchronous launch failures
  and have bounded runtimes.
- Re-running Linux bootstrap no longer stops a running Docker service merely
  to configure socket activation.
- Linux setup skips absent optional daemons, tolerates absent saved ALSA state,
  and avoids SIGPIPE false negatives when checking large firmware modules.
- Session helper links are created before enabling the night-light schedule.
  Font downloads use private temporary files with cleanup on exit.
- The standalone Git-profile and cleanup helpers are executable.

The earlier tmux/Kitty fixes were also reviewed: watcher locks are scoped to
server sockets, slow live owners retain ownership, unchanged options are not
rewritten, Git lookups are cached for three seconds, and naming checks run on
creation hooks with a 30-second fallback. A real integration test starts two
isolated servers, verifies publication on both, terminates one owner, and
verifies follower takeover without affecting the other server. Kitty uses an
explicit shortcut list and confirms closing running commands.

**Scope still requiring a Linux host**

Linux shell behavior and filesystem operations were tested with isolated homes
and mocked system commands. Lua files were syntax checked and desktop command
references were reviewed. Native Quickshell/QML, Hyprland/hyprlock/hypridle,
rofi/dunst, systemd dependency ordering, monitor profiles, suspend/resume,
audio, and gamma control still need runtime validation on Fedora.

No full bootstrap, package upgrade, real Docker stop/restart, or Linux system
change was executed for this review. The existing Mac Git identity and personal
application settings were not rewritten. JavaScript fixes reached through live
symlinks are in place; Linux setup changes take effect when applied on Linux.

Run the regression suite again with:

```sh
INITD_TEST_TMUX=1 node --test shared/*.test.mjs
```

On Fedora, also validate the native compositor and user units before checking
the desktop behavior interactively:

```sh
Hyprland --verify-config --config ~/.config/hypr/hyprland.lua
systemd-analyze --user verify ~/.config/systemd/user/initd-hyprland-session.service \
  ~/.config/systemd/user/night-light.service \
  ~/.config/systemd/user/night-light-schedule.service \
  ~/.config/systemd/user/night-light-schedule.timer
```

## Follow-up JavaScript conversions

- `linux/scripts/audio-ports.mjs` replaces the AWK parser with pactl card JSON
  parsing. Quickshell reads a JSON map, preserving display names containing
  separators or newlines. Duplicate port tokens remain unmapped so a different
  card cannot hide an endpoint. Command failures clear stale availability.
  Linux setup migrates the old owned shell-script link and preserves unrelated
  user files.
- `macos/brewinstall` is now a JavaScript entry point backed by
  `macos/brewinstall.mjs`. The CLI name is unchanged and Node is required.
  Package arguments are validated before editing, explicit kinds are checked,
  existing entries with comments/options are recognized, and failed installs
  retain the entry for retry.
- Nine additional regression tests cover parsing, CLI errors, Brewfile changes,
  subprocess failures and link migration. All 81 suite tests pass. The changed
  JavaScript and shell syntax checks pass; the QML JSON handler was also executed
  in isolation with valid, empty and malformed output. Native Fedora audio and
  Quickshell runtime checks remain outstanding. No Homebrew installs were run.

## Documentation and efficiency follow-up

Reviewed all 14 tracked Markdown documents for repository paths, configuration
instructions, and consistency with the current helpers. Corrected the tmux
refresh delay, session practice workflow, status colour, Fish environment versus
interactive overrides, a removed Docker helper path, shell-check coverage,
Neovim's mise description, and Colima service instructions. Documented the
21-icon tmux pool and its random assignment without repeats until exhausted.
The README now links the JavaScript guide and this review.

The script review found no immediate efficiency change needed for ordinary
use. The recurring tmux path already elects one owner per socket, skips agent
discovery when idle, shares a pane snapshot and one open-file scan, reads logs
incrementally, caches slower lookups, and publishes only changed options in a
batch. Desktop helpers run on demand; setup helpers' synchronous operations
preserve dependent installation order. Fish defers mise activation until the
first command and keeps interactive setup out of noninteractive shells.

This was a source review with regression checks, not a CPU/memory benchmark.
Large first-time transcript reads and SQLite fallback queries remain workloads
to measure if status updates become slow. Linux desktop runtime validation
still requires a Fedora host. No script logic was changed in this follow-up.

## Full JavaScript and Mac review

Reviewed the JavaScript helpers for subprocess overhead, log parsing, cache
lifetime, asynchronous error handling, and filesystem updates. The deeper
review found and fixed an allocation problem in `sessionState()`: every chunk
of an unfinished transcript record was concatenated with all preceding chunks.
For long tool output or image records, this repeatedly copied the growing line.
The reader now retains fragments and assembles each complete record once.

A synthetic benchmark on this Mac used Node 24.21.0 with `--expose-gc`, one
16 MiB JSON payload followed by a model event, and a fresh process for each
version. Timings exclude fixture creation; RSS growth is the process's
after-minus-before resident memory, not a peak-memory measurement.

| Measurement | Before | After |
| --- | --- | --- |
| Read and parse elapsed time | 188 ms | 14 ms |
| Process CPU time | 271 ms | 17 ms |
| RSS growth | 1,002 MiB | 50 MiB |

These are single-run stress measurements, not an estimate of everyday savings.
The regression checks copy volume against input size, validates a large Unicode
record, and verifies that the incomplete next record resumes correctly. Existing
rotation, truncation, split UTF-8, and agent-isolation tests also pass.

Live Mac checks:

- All 101 regression tests passed, including isolated tmux servers, after
  allowing socket access outside the sandbox. All 28 JavaScript files passed
  syntax and correctness lint; all 14 shell and 2 Fish files passed syntax.
- Homebrew's Brewfile check passed and mise reported no missing tools.
  All 10 managed links resolve to their intended repository source.
- Exactly one live tmux watcher was present for one attached client. It
  automatically restarted after the source edit. Four read-only discovery
  samples took 64–79 ms, including 25–29 ms for `ps` and 35–38 ms for `lsof`.
  The profiler suppressed cache writes and did not include status publication.
- Five Fish invocations took 5–7 ms noninteractively. Interactive `fish -ic true`
  took 145 ms on the first sample and 77–81 ms subsequently, with tmux auto-attach
  disabled. This measures shell initialization, not a terminal window or prompt.
- Colima was the only Homebrew service listed. Docker was reachable, with zero
  running containers; Colima used aarch64, Virtualization.framework and virtiofs.
  Its existing login-service policy was retained.
- Docker credentials use `osxkeychain`, the Compose/plugin path is configured,
  and the Claude status hook matches the managed helper. Both JSON files are
  mode `0600`; no settings were rewritten.
- Ghostty, tmux's parse-only check, and Mise/Starship TOML validation passed.
  Neovim startup loaded all 39 installed plugin configurations successfully.
  macOS press-and-hold/key-repeat values match `macos/defaults.sh` (0, 15, 2).

No additional JavaScript refactor was justified by these checks. Initial log
reads still require memory proportional to the largest record, and external
process/database work can lengthen a watcher cycle. Linux helpers received
source review and mocked tests; native Linux validation remains deferred.
