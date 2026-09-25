# macOS bootstrap review — handoff notes

The Linux bootstrap was reviewed and tightened on 2026-09-25 (commit "Harden
Linux bootstrap for fresh machines and idempotent re-runs"). This file lists
the same review for `macos/bootstrap.sh`. Delete it once that review is done.

To start on the Mac, ask Claude Code:

> Read docs/macos-bootstrap-review.md and do the same review/optimisation for
> the macOS bootstrap. Verify against this machine's live state and run the tests.

## 1. Must fix: bare `mise exec -- node` (same bug as Linux)

**Problem:** once `~/.config/mise` is linked, `mise exec -- node` with no tool
named installs **every** missing tool in the global config before running node.
It never installs node alone. I checked this in a scratch `HOME` with a
two-tool config: `mise exec -- jq` installed both tools, while
`mise exec aqua:jqlang/jq -- jq` installed only jq.

**Effect on a fresh Mac:** the first node step after `link.sh` silently becomes
the whole toolchain install (dotnet, Go builds, LSPs). If any one tool fails,
bootstrap stops under `set -e` before later steps (fish, git profile, and so
on) run.

**Where it happens:**
- `macos/bootstrap.sh` — `ensure_docker_config` (`docker-config.mjs`)
- `macos/bootstrap.sh` — `setup_git_profile` (`git-profile.mjs`)
- `macos/bootstrap.sh` — the statusLine step (`claude-statusline.mjs`)

**Fix:** use the one Linux uses. Add a helper and route all three calls
through it:

```bash
run_node() {
  mise -C "${ROOT_DIR}" exec node@lts -- node "$@"
}
```

Also:
- Update the comment above the `docker-config.mjs` call.
- Update any `tests/macos/bootstrap.test.mjs` stubs that expect
  `exec -- node` (the Linux equivalent was in
  `tests/linux/linux-setup.test.mjs`).
- In CLAUDE.md ("Plain .mjs, no toolchain"), drop "(macOS still uses the bare
  form.)".

## 2. Worth checking: idempotence and speed of re-runs

On Linux, each step checks state first, so a re-run on a configured machine
makes no sudo, network or package-manager calls. Check each macOS step the same
way:

- **`brew bundle`:** runs every time. It is already idempotent, but check
  whether `brew bundle check --file ...` could skip it when nothing is missing.
  Time it on the Mac before deciding.
- **`ensure_fish`:** `fisher update` hits the network on every run (same on
  Linux, left as is). Only change it if it is slow.
- **`macos/defaults.sh`:** does it `killall` Dock/Finder/SystemUIServer even
  when nothing changed? If so, gate the restart on an actual change.
- **`ensure_local_fonts`, `ensure_tmux_terminfo`:** confirm they skip when
  already current.
- **`mise trust`:** a symlinked global config was trusted without it in the
  Linux test. The step is harmless, so keep it.

## 3. Things that were checked and are intentional (don't "fix")

- On a personal machine, `setup_git_profile` asks personal/work on every
  interactive run. That is by design: `tests/shared/install.test.mjs` asserts
  that `personal` never writes `local.gitconfig`.
- `shared/` code must not branch on OS. Every fix above belongs in
  `macos/bootstrap.sh`.

## 4. Verify

```bash
for f in macos/bootstrap.sh macos/defaults.sh macos/update.sh; do bash -n "$f" && echo "OK $f"; done
node --test tests/macos/*.test.mjs tests/shared/install.test.mjs
INITD_TEST_TMUX=1 node --test 'tests/**/*.test.mjs'   # quoted glob — see CLAUDE.md
```

Then run each changed function against the live Mac with `sudo` stubbed out,
to confirm a configured machine makes no privileged calls:

```bash
bash -c 'source macos/bootstrap.sh; sudo(){ echo "SUDO: $*"; }; ensure_fish'
```
