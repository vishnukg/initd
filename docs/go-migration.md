# Go migration plan

This document tracks the long-running migration from the current Bash-based
`initd` setup to a Go CLI. The migration should be done slowly, one feature at a
time, so the existing setup stays reliable while the Go version becomes easier to
understand, test, and maintain.

## Goals

- Keep the existing Bash setup working until the Go migration is complete.
- Move repo-specific setup logic into a clear, tested Go CLI.
- Use the Go standard library before adding third-party dependencies.
- Use the standard `testing` package for tests.
- Optimize for clarity and readability over clever abstractions.
- Make every migration step small enough to resume safely days or weeks later.
- Remove Bash files only after the Go CLI fully replaces their behavior.

## Non-goals for the early migration

- Do not rewrite the whole bootstrap flow in one change.
- Do not replace working shell scripts before the equivalent Go command is tested.
- Do not introduce CLI frameworks such as Cobra or Viper at the start.
- Do not turn this into a generic dotfile manager. The CLI should remain specific
  to this `initd` repo until there is a clear reason to generalize it.

## Compatibility rule

The existing commands remain the source of truth until each Go replacement is
tested and intentionally wired in:

```bash
bash ~/.config/initd/bootstrap.sh
~/.config/initd/scripts/stow.sh
~/.config/initd/scripts/cleanup.sh
~/.config/initd/scripts/git-profile.sh personal
~/.config/initd/scripts/git-profile.sh work
~/.config/initd/scripts/test-install-behavior.sh
```

During the migration, it must always be safe to fall back to the current Bash
commands.

## Current migration status

Completed:

- Step 1 started: `go.mod`, `cmd/initd/main.go`, and basic CLI tests exist.
- The Go CLI currently supports only `help` and `version`.
- Step 2 completed: `internal/config` models home/root paths, managed links,
  legacy links, Stow package names, and Git profiles.
- A root `Makefile` exists for Go development:
  - `make test` runs `go test ./...`.
  - `make build` builds the CLI into `bin/initd`.
- No Bash entrypoints have been changed.

Next step:

- Continue with Step 3 by adding a read-only `initd doctor` command.

## Preferred Go project structure

Start with a small Go module in this repo:

```text
initd/
├── cmd/
│   └── initd/
│       └── main.go
├── internal/
│   ├── backup/
│   ├── cleanup/
│   ├── config/
│   ├── doctor/
│   ├── gitprofile/
│   ├── link/
│   ├── platform/
│   │   └── darwin/
│   └── run/
├── go.mod
└── ...
```

Keep this structure boring:

- `cmd/initd` contains only CLI wiring, argument parsing, output, and exit codes.
- `internal/...` contains testable behavior.
- Use `internal` because it is a Go visibility mechanism supported by the Go
  toolchain.
- Avoid adding `pkg`, `src`, `app`, or framework-style directories.
- Split packages only when it improves readability.

If the first implementation is tiny, it is fine to begin with fewer packages and
split them later.

## Standard library choices

Use these standard library packages first:

| Need | Package |
|---|---|
| CLI flags | `flag` |
| Filesystem operations | `os`, `io/fs`, `path/filepath` |
| Symlink inspection | `os.Lstat`, `os.Readlink`, `filepath.EvalSymlinks` |
| External commands | `os/exec` |
| Output | `fmt`, `io` |
| Logging, if needed | `log/slog` |
| Tests | `testing`, `t.TempDir`, table-driven tests |

Avoid third-party packages until there is a specific, documented reason.

## Core design guidelines

### Keep internal packages testable

Internal packages should return errors instead of exiting:

```go
if err != nil {
    return fmt.Errorf("backup %s: %w", path, err)
}
```

Only `cmd/initd/main.go` should decide when to print an error and exit.

### Pass environment explicitly

Avoid hard-coding `$HOME` and repo paths throughout the code. Prefer a small
environment/config type:

```go
type Env struct {
    HomeDir string
    RootDir string
}
```

This makes tests easy because they can use temporary directories instead of the
real home directory.

### Prefer clear data models

Represent managed paths directly:

```go
type Link struct {
    Label  string
    Target string // relative to HomeDir
    Source string // relative to RootDir
}
```

Keep link data relative and let `Env` expand it to absolute paths when needed.
This avoids storing both relative and absolute versions of the same path.

The current managed runtime paths are:

| Runtime path | Source path |
|---|---|
| `~/.config/kitty` | `kitty/.config/kitty` |
| `~/.config/mise` | `mise/.config/mise` |
| `~/.config/nvim` | `nvim/.config/nvim` |
| `~/.zshrc` | `zsh/.zshrc` |
| `~/.zprofile` | `zsh/.zprofile` |
| `~/.gitconfig` | `git/profiles/personal.gitconfig` or `git/profiles/work.gitconfig` |

### Keep logs readable

This repo values simple, developer-friendly logs. Go output should preserve that
style:

- Say what is being checked or changed.
- Say where backups are written.
- Say why a path is skipped.
- Avoid noisy debug output by default.

## Testing strategy

Every migrated feature needs Go tests before it replaces shell behavior.

Use either:

```bash
go test ./...
make test
```

Build the Go CLI with:

```bash
make build
```

Use temporary directories:

```go
home := t.TempDir()
root := t.TempDir()
```

Prefer table-driven tests for behavior variations:

```go
tests := []struct {
    name    string
    setup   func(t *testing.T, env Env)
    wantErr bool
}{
    // cases
}
```

Name Go tests with a clear given/when/then pattern:

```go
func TestGivenManagedSymlink_WhenCleanupRuns_ThenLinkIsRemoved(t *testing.T) {
    // Arrange
    // Act
    // Assert
}
```

Use the Arrange/Act/Assert structure in tests so future maintainers can quickly
see the setup, behavior under test, and expected result.

Tests should focus on observable filesystem behavior:

- What symlink exists?
- What target does it resolve to?
- Was a user file backed up?
- Was an unrelated file left alone?
- Did dry-run avoid changes?
- Was a useful error returned?

The existing shell behavior test remains important during the migration:

```bash
~/.config/initd/scripts/test-install-behavior.sh
```

## Sequential migration steps

### Step 1: Add the Go module and CLI skeleton

Add:

```text
go.mod
cmd/initd/main.go
```

Initial commands:

```bash
go run ./cmd/initd help
go run ./cmd/initd version
```

Requirements:

- No existing Bash behavior changes.
- No bootstrap wiring changes.
- `go test ./...` passes.
- CLI output is simple and readable.

### Step 2: Add shared config/path modeling

Add an internal package for repo-specific paths:

```text
internal/config
```

Responsibilities:

- Store `HomeDir` and `RootDir`.
- Expand home-relative runtime paths.
- Expand repo-relative source paths.
- Return the list of current managed links.
- Return the list of known legacy links.
- Return available Git profiles.

Tests:

- Managed links resolve correctly for fake home and repo roots.
- Git profile paths resolve correctly.
- Legacy path definitions match current shell behavior.

No shell scripts should call Go yet.

### Step 3: Add read-only `initd doctor`

Add:

```bash
go run ./cmd/initd doctor
```

Responsibilities:

- Detect the current OS.
- Confirm the repo root exists.
- Confirm managed source paths exist.
- Inspect runtime symlink state.
- Report missing, correct, and incorrect links.
- Check required external commands when relevant: `git`, `brew`, `mise`, `stow`.
- Report the current Git profile symlink state.

Requirements:

- Read-only command.
- No filesystem mutation.
- Good output for a developer trying to understand what is wrong.

Tests:

- Correct links are reported as correct.
- Missing links are reported as missing.
- Wrong symlink targets are reported as incorrect.
- Missing source paths produce a clear failure.

### Step 4: Replace `scripts/git-profile.sh` behavior in Go

Add:

```bash
go run ./cmd/initd git-profile current
go run ./cmd/initd git-profile personal
go run ./cmd/initd git-profile work
```

Responsibilities:

- Validate profile names.
- Switch `~/.gitconfig` to the selected profile.
- Report the active profile.
- Preserve or back up unmanaged files according to current shell behavior.
- Leave existing shell script untouched at first.

Tests:

- Switches from no profile to personal.
- Switches from personal to work.
- Reports current profile.
- Rejects unknown profiles.
- Handles unmanaged `.gitconfig` safely.
- Handles unrelated symlinks safely.

Only after tests pass and behavior is manually compared, consider changing
`scripts/git-profile.sh` into a compatibility wrapper around the Go command.

### Step 5: Add backup primitives

Add:

```text
internal/backup
```

Responsibilities:

- Move unmanaged files into `~/.config/initd-backups/<timestamp>/`.
- Preserve the original home-relative path under the backup root.
- Back up regular files, directories, and symlinks.
- Treat missing paths as no work.
- Return clear errors on failure.

Tests:

- Backs up a regular file.
- Backs up a directory.
- Backs up a symlink without following it unexpectedly.
- Preserves nested relative paths.
- Does nothing for missing paths.
- Does not silently swallow permission or filesystem errors.

This package becomes the shared foundation for later Go commands.

### Step 6: Replace `scripts/cleanup.sh` behavior in Go

Add:

```bash
go run ./cmd/initd cleanup
go run ./cmd/initd cleanup --dry-run
go run ./cmd/initd cleanup --legacy-only
```

Responsibilities:

- Remove only current managed symlinks.
- Remove known legacy initd symlinks.
- Leave real user files untouched.
- Leave symlinks outside initd ownership untouched.
- Support dry-run without changing the filesystem.
- Support legacy-only mode.
- Remove empty managed directories only when safe.

Tests:

- Removes current managed links.
- Removes legacy links.
- Leaves non-symlink files.
- Leaves unrelated symlinks.
- Dry-run changes nothing.
- Legacy-only skips current managed links.
- Empty directory cleanup is safe.

Only after tests pass and behavior is manually compared, consider changing
`scripts/cleanup.sh` into a compatibility wrapper around the Go command.

### Step 7: Add `initd link --prepare`

Add:

```bash
go run ./cmd/initd link --prepare
```

Responsibilities:

- Remove known legacy Git shims.
- Remove known legacy zsh shims.
- Remove the legacy mise config symlink.
- Create the default Git profile link if needed.
- Fold existing managed config directories into direct symlinks when safe.
- Back up unmanaged config directories before Stow runs.

Tests:

- Removes old XDG Git config symlink.
- Removes old legacy Git config directory symlink.
- Removes old zsh config symlink.
- Replaces known legacy `.zshrc` and `.zprofile` loader files.
- Removes legacy mise config symlink.
- Folds directories containing only initd-managed symlinks.
- Backs up directories containing unmanaged files.
- Creates default personal Git profile link.

At this step, GNU Stow can still be run by the existing shell script.

### Step 8: Add `initd link`

Add:

```bash
go run ./cmd/initd link
```

Responsibilities:

- Run the same preparation as `initd link --prepare`.
- Call GNU Stow using `os/exec`:

  ```bash
  stow --restow --dir <root> --target <home> kitty mise nvim zsh
  ```

- Verify that the managed links are fully installed.
- Show clear errors if Stow reports conflicts.

Tests:

- Unit-test preparation and verification logic with temp directories.
- Keep external Stow execution thin and easy to inspect.
- Where possible, use integration tests that skip when `stow` is unavailable.

Only after behavior matches `scripts/stow.sh`, consider changing
`scripts/stow.sh` into a compatibility wrapper around the Go command.

### Step 9: Consider replacing GNU Stow

This is optional and should happen only after `initd link` is stable.

The repo currently prefers direct symlinks for major config directories:

```text
~/.config/kitty -> <repo>/kitty/.config/kitty
~/.config/mise  -> <repo>/mise/.config/mise
~/.config/nvim  -> <repo>/nvim/.config/nvim
~/.zshrc        -> <repo>/zsh/.zshrc
~/.zprofile     -> <repo>/zsh/.zprofile
```

Because of that, Go may eventually be able to manage all links directly without
GNU Stow.

Requirements before removing Stow:

- Go link tests cover every managed path.
- Go link behavior matches the existing install behavior test.
- README no longer claims GNU Stow is the active implementation.
- Bootstrap no longer requires Stow unless another feature needs it.

### Step 10: Add macOS platform checks

Add:

```text
internal/platform/darwin
```

Responsibilities:

- Check Xcode Command Line Tools.
- Check or install Homebrew.
- Prepare a temporary Brewfile.
- Skip Docker cask when `/Applications/Docker.app` already exists outside
  Homebrew.
- Run `brew bundle`.
- Verify Docker Desktop is available.

Requirements:

- Preserve current behavior from `platforms/darwin/bootstrap.sh`.
- Keep external commands explicit and easy to read.
- Do not hide command output that developers need for troubleshooting.

Tests:

- Unit-test Brewfile filtering.
- Unit-test command planning where possible.
- Keep real Homebrew execution out of normal unit tests.

### Step 11: Move Oh My Zsh setup into Go

Add Go behavior for:

- Detecting a valid Oh My Zsh checkout.
- Checking the origin remote.
- Fast-forwarding clean checkouts.
- Backing up dirty, invalid, or non-fast-forwardable checkouts.
- Cloning a fresh checkout when needed.

Tests:

- Missing directory plans a clone.
- Valid clean checkout plans update.
- Dirty checkout plans backup and clone.
- Invalid remote plans backup and clone.

Use real `git` in integration tests only when that can be done safely in temp
directories.

### Step 12: Add `initd bootstrap`

Add:

```bash
go run ./cmd/initd bootstrap
```

Responsibilities:

- Detect OS.
- Run macOS bootstrap flow on Darwin.
- Reject unsupported OSes clearly.
- Run Homebrew setup.
- Run Oh My Zsh setup.
- Run `initd link`.
- Run `mise trust`.
- Run `mise install --yes`.
- Apply macOS defaults.
- Ensure default Git profile.
- Run final verification or `initd doctor`.

At first, this command may still call some existing shell scripts for pieces that
have not moved yet. Over time, those calls should disappear as Go equivalents
are completed.

Requirements:

- `bootstrap.sh` remains available as the stable user entrypoint.
- Fresh-machine behavior is not broken.
- Errors explain which step failed and what to rerun.

### Step 13: Convert shell scripts to compatibility wrappers

Only after a Go command has matching tests and manual behavior comparison, the
corresponding shell script may become a thin wrapper.

Examples:

```bash
scripts/git-profile.sh -> initd git-profile "$@"
scripts/cleanup.sh     -> initd cleanup "$@"
scripts/stow.sh        -> initd link "$@"
```

Requirements:

- Wrapper still works when run directly.
- Wrapper prints a clear message if the Go binary is missing.
- Existing README commands still work.
- Existing shell tests still pass.

### Step 14: Update bootstrap to build or run the Go CLI

After the Go bootstrap command is stable, `bootstrap.sh` can become a small
compatibility entrypoint:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -x "${ROOT_DIR}/bin/initd" ]]; then
  go build -o "${ROOT_DIR}/bin/initd" "${ROOT_DIR}/cmd/initd"
fi

exec "${ROOT_DIR}/bin/initd" bootstrap "$@"
```

Fresh-machine bootstrapping needs special care because Go may not exist yet. Do
not make this switch until there is a clear bootstrap strategy.

Possible strategies:

- Keep enough Bash to install Homebrew and Go first.
- Build the CLI after Homebrew installs Go.
- Provide a prebuilt binary later, if desired.

### Step 15: Remove replaced Bash files

Only remove Bash files after all of these are true:

- `initd bootstrap` fully replaces `bootstrap.sh` and
  `platforms/darwin/bootstrap.sh`.
- `initd link` fully replaces `scripts/stow.sh`.
- `initd cleanup` fully replaces `scripts/cleanup.sh`.
- `initd git-profile` fully replaces `scripts/git-profile.sh`.
- Tests cover backup, cleanup, linking, Git profile switching, and bootstrap
  planning.
- README usage points to the Go CLI.
- Fresh-machine setup has a working entrypoint.

When removing Bash files, keep any useful docs by moving relevant explanations
into README or Go-focused docs.

## Resume checklist for future agents

Before continuing this migration:

1. Read this document.
2. Check `git status --short`.
3. Run the current validation commands if relevant:

   ```bash
   bash -n bootstrap.sh platforms/darwin/bootstrap.sh platforms/darwin/macos.sh scripts/stow.sh scripts/cleanup.sh scripts/git-profile.sh scripts/logging.sh scripts/fs.sh
   ~/.config/initd/scripts/test-install-behavior.sh
   ```

4. Check whether `go.mod` exists.
5. If Go code exists, run:

   ```bash
   go test ./...
   ```

6. Work on the next incomplete migration step only.
7. Do not wire Bash scripts to Go until the Go behavior has tests.
8. Do not remove Bash scripts until the full migration is complete.

## Completion criteria

The migration is complete when:

- A user can run the Go CLI to bootstrap a supported machine.
- The Go CLI manages config links, cleanup, Git profiles, backups, Homebrew
  orchestration, Oh My Zsh, mise, and macOS defaults.
- The old Bash behavior is either removed or kept only as a tiny bootstrap shim.
- Tests cover the risky filesystem behavior.
- README explains the Go workflow.
- The repo no longer depends on GNU Stow unless there is a deliberate reason to
  keep it.
