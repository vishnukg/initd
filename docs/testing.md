# Tests

Run commands from the repository root. The suite requires Node.js with
`node:sqlite` support and Fish; the full integration run also requires tmux.
There is no dependency installation or build step for the tests.

Run the full suite, including isolated tmux servers and interactive Fish shells:

```sh
INITD_TEST_TMUX=1 node --test tests/linux/*.test.mjs tests/macos/*.test.mjs tests/shared/*.test.mjs
```

The suite lives in the `tests/` directory, organized by platform and scope:

| Directory | Scope |
| --- | --- |
| `tests/linux/` | Linux setup, Firefox, Chrome, audio, and night-light |
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

The remaining files cover bootstrap configs, installation, Linux setup, Fish,
night light, and enterprise quotas. Run an individual file with
`node --test tests/<platform>/<name>.test.mjs`; enable `INITD_TEST_TMUX=1` for real tmux
and terminal integration checks. Without it those checks are explicitly skipped.

Keep unit tests isolated from the user's files and services: inject command
runners, cache readers, battery readers, and cache cleanup. Use temporary homes
for integration tests. Wait for observable readiness with a deadline instead of
fixed sleeps, and retain real subprocess concurrency where races are the behavior
being tested. Do not trade away those checks just to lower the runtime.

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
