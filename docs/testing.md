# Tests

Run commands from the repository root. The suite requires Node.js with
`node:sqlite` support; Fish and tmux are needed for the integration checks and
those checks skip without them. The live Linux contract checks need the relevant
audio/display session running when its binary is installed. There is no dependency
installation or build step for the tests.

Run a platform's tests together with the shared tests:

```sh
./linux/test.sh
./macos/test.sh
```

Both scripts work from any directory and enable isolated tmux integration checks
by default. Set `INITD_TEST_TMUX=0` to skip those checks. Extra arguments are passed
to Node's test runner, for example:

```sh
./macos/test.sh --test-name-pattern='cache sweep'
```

Run both platforms together, including isolated tmux servers and interactive Fish shells:

```sh
INITD_TEST_TMUX=1 node --test 'tests/**/*.test.mjs'
```

The suite lives in the `tests/` directory, organized by platform and scope:

| Directory | Scope |
| --- | --- |
| `tests/linux/` | Linux setup, Firefox, Chrome, audio, night-light, and the Quickshell bar logic |
| `tests/macos/` | Homebrew and macOS bootstrap helpers |
| `tests/shared/` | Cross-platform links, Fish, tmux, status, agents, and shared config helpers |

The individual files are organized as follows:

| File | Scope |
| --- | --- |
| `shared/agent-transcripts.test.mjs` | Models, quota events, streaming reads, truncation and rotation |
| `shared/agent-discovery.test.mjs` | Process ownership, open-file binding and SQLite fallback |
| `shared/status-publisher.test.mjs` | Rendering, publication, caching and session names |
| `shared/watcher-lifecycle.test.mjs` | Locks, atomic writes and real watcher takeover |
| `linux/audio-ports.test.mjs` | Audio parsing and command-line behavior |
| `macos/brewinstall.test.mjs` | Argument validation, Brewfile updates and failure handling |
| `macos/bootstrap.test.mjs` | Fresh/repeat bootstrap ordering, existing apps, font migration, terminfo, Colima service ownership, gh auth, Git identity, and update orchestration |
| `shared/fonts.test.mjs` | Private font sync: clone, update, and every warn-and-continue path |
| `linux/bar-logic.test.mjs` | Weather icons and colours, load colours, audio device classification, QML call sites |
| `linux/display-menu.test.mjs` | The `hyprmoncfg status --json` contract DisplayMenu.qml parses |

The remaining files cover bootstrap configs, installation, Linux setup, Fish,
night light, and enterprise quotas.

Fixtures prove a parser is self-consistent; they cannot notice the day the tool
feeding it changes its output. Parsers for another program's output therefore
carry a **contract check** beside the unit tests: it runs the real binary, asserts
only the shape assumptions the parser depends on (`pactl`’s port objects,
optional availability strings, and the display/profile fields read by the menu),
and skips when the binary is absent. Keep those assertions to what the consumer actually reads, so a
harmless new field in the tool never fails the suite.

Checks that need a tool the host may not have are declared with `skip`, never
left to fail at import: `tests/shared/fish-config.test.mjs` skips when Fish is
absent, and the tmux integration checks skip without `INITD_TEST_TMUX=1`. A
skipped check is reported as skipped, so a green run never means "ran nothing".

Run an individual file with
`node --test tests/<platform>/<name>.test.mjs`; enable `INITD_TEST_TMUX=1` for real tmux
and terminal integration checks. Without it those checks are explicitly skipped.

Keep unit tests isolated from the user's files and services: inject command
runners, cache readers, battery readers, and cache cleanup. Use temporary homes
for integration tests. Wait for observable readiness with a deadline instead of
fixed sleeps, and retain real subprocess concurrency where races are the behavior
being tested. Do not trade away those checks just to lower the runtime.

A Bash helper is tested by sourcing its script - every bootstrap guards its
own `main` - and shadowing only the commands that would touch the machine. A
shell function is enough for a plain call; a command reached through `env`, or
by absolute path, needs a real executable on `PATH`. Those stubs are symlinks
to one script whose behaviour arrives in the environment, because macOS spends
~250 ms scanning each newly written executable the first time it runs, and a
script per stub costs more than the rest of the suite. Have each stub record its
own invocation, so a step that must NOT run is asserted by absence rather than
by the side effect it failed to leave.

Name what an Act returns for the role it plays in the assertion - `legacyDefault`,
`claimAfterHolderDied`, `afterUnregistration`. A name that only counts calls
(`fooResult2`) tells a later reader nothing about what went wrong.

Tests use **Arrange, Act, Assert**:

- **Arrange:** prepare inputs, isolated files, dependency fakes, and cleanup.
- **Act:** call the production function or command being tested. Give returned
  values names that make their role clear.
- **Assert:** check returned values, recorded calls, and observable side effects.
  Keep production calls out of equality assertions so the operation is visible.

Use named, table-driven tests for independent input variations. For lifecycle
tests where order matters (rotation, retries, ownership changes), capture each
stage's result before checking it, or label successive Arrange/Act/Assert phases.
Do not move an observation past a mutation that changes what it would see.

For synchronous errors, define a named operation in Act and pass it to
`assert.throws` in Assert. For asynchronous errors, start the operation in Act
and immediately check its promise with `assert.rejects` in Assert. Record mock
calls and check them in Assert; fixture setup and timeout guards may throw when
the test cannot proceed.

```js
test('a non-agent command has no agent pill', () => {
    // Arrange
    const command = 'fish';

    // Act
    const rendered = agentPill(command);

    // Assert
    assert.equal(rendered, '');
});
```

A test must identify the regression it catches. Use expected values independent
of production constants and construct fixtures that actually reach the named
failure: a reused PID needs matching old records, not an absent PID. Assert real
side effects as well as reported results, and require fresh publication after
watcher takeover rather than accepting the previous owner's cached output.
Pin file timestamps in the past when checking that a write did not happen.

Remove assertions implied by stronger checks (such as checking glyph shape after
asserting the exact glyph), and avoid prescribing implementation details with no
observable consequence. Source checks at the QML boundary are limited wiring
checks, not evidence that the UI runs correctly. Live contracts must allow valid
empty profiles and hardware variations; never require fields the consumer does
not read. When strengthening a regression test, deliberately break the relevant
behavior in a disposable copy and confirm the test fails for the intended reason.
