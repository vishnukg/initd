# initd configuration review — 2026-09-12

The available automated checks pass on the Mac after the fixes below. The
review covers the JavaScript helpers, bootstrap/update/link/cleanup paths,
terminal and shell configuration, Neovim, and the Linux desktop configuration.
It is not a claim that every Linux service or hardware feature has been run:
Hyprland, Quickshell, systemd, and the laptop hardware are unavailable here.

| Verification | Result |
| --- | --- |
| Full regression suite, including tmux integration | 81 passed; none skipped |
| JavaScript syntax and correctness lint | 19 files passed in the initial review; conversion checks below |
| Shell syntax | 17 Bash/shell files and 2 tracked fish files passed before the conversions |
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
