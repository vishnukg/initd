# TypeScript migration guide

This guide describes how to migrate `initd` from Bash scripts to a TypeScript CLI without breaking the current bootstrap flow.

## Goal

Move the long-lived setup logic into a tested TypeScript CLI while keeping a small Bash entrypoint for first-run compatibility.

The final shape should be:

```text
Bash shim        -> minimal first-run host bootstrap
TypeScript CLI   -> link, cleanup, git-profile, brewinstall, doctor, bootstrap orchestration
Docker           -> repeatable Node development, builds, and tests
```

Docker should provide the base Node development environment. It should not be the default way to run the real macOS bootstrap, because host setup needs direct access to Homebrew, Xcode Command Line Tools, macOS defaults, `/Applications`, and the user's real `$HOME`.

## Why TypeScript

TypeScript is a good fit for `initd` because most of the repo logic is orchestration:

- path and symlink management
- config backups
- platform checks
- command execution
- user-friendly logs
- behavior tests using temporary home directories

Compared with Bash, TypeScript should make the code easier to read, test, and refactor. Compared with Go, it should be faster to iterate on for this repo, although Go would still be a strong choice if a single static binary became the top priority.

## Migration principles

1. Keep the existing Bash scripts working until each replacement is proven.
2. Port one command at a time.
3. Start with commands that can be tested safely using temporary `$HOME` directories.
4. Preserve current behavior before improving behavior.
5. Keep logs simple and explicit so developers can follow what the tool is doing.
6. Do not make Docker the production bootstrap path.

## Proposed TypeScript layout

```text
initd/
├── package.json
├── tsconfig.json
├── Dockerfile
├── bin/
│   └── initd
├── src/
│   ├── cli.ts
│   ├── commands/
│   │   ├── bootstrap.ts
│   │   ├── brewinstall.ts
│   │   ├── cleanup.ts
│   │   ├── doctor.ts
│   │   ├── git-profile.ts
│   │   └── link.ts
│   ├── lib/
│   │   ├── fs.ts
│   │   ├── logging.ts
│   │   ├── paths.ts
│   │   └── shell.ts
│   └── platform/
│       └── darwin.ts
└── test/
    ├── cleanup.test.ts
    ├── git-profile.test.ts
    └── link.test.ts
```

## Command mapping

| Current Bash entrypoint | Future TypeScript command |
|---|---|
| `bootstrap.sh` | `initd bootstrap` |
| `platforms/darwin/bootstrap.sh` | `initd bootstrap --platform darwin` |
| `scripts/link.sh` | `initd link` |
| `scripts/cleanup.sh` | `initd cleanup` |
| `scripts/cleanup.sh --dry-run` | `initd cleanup --dry-run` |
| `scripts/git-profile.sh personal` | `initd git-profile personal` |
| `scripts/git-profile.sh work` | `initd git-profile work` |
| `scripts/brewinstall.sh ...` | `initd brewinstall ...` |
| `scripts/test-install-behavior.sh` | `vitest` behavior tests |

## Phase 1: Add TypeScript scaffolding

Add the TypeScript project beside the existing Bash scripts. Do not replace any existing script in this phase.

Suggested tooling:

```bash
npm init -y
npm install commander execa
npm install --save-dev typescript tsx tsup vitest @types/node
```

Suggested scripts:

```json
{
  "scripts": {
    "build": "tsup src/cli.ts --format esm --dts --clean --out-dir dist",
    "initd": "tsx src/cli.ts",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  }
}
```

Initial CLI targets:

```bash
npm run initd -- link
npm run initd -- cleanup --dry-run
npm run initd -- git-profile personal
npm run initd -- doctor
```

## Phase 2: Port shared helpers

Port helpers before porting full commands.

| Bash helper | TypeScript module |
|---|---|
| `scripts/logging.sh` | `src/lib/logging.ts` |
| `scripts/fs.sh` | `src/lib/fs.ts` |
| `scripts/paths.sh` | `src/lib/paths.ts` |
| command execution in scripts | `src/lib/shell.ts` |

These helpers should centralize:

- repo root detection
- home directory resolution
- symlink target resolution
- safe path existence checks
- backup path creation
- command execution
- consistent logging

## Phase 3: Port `git-profile`

Port `scripts/git-profile.sh` first because it is small and useful.

The new command should support:

```bash
initd git-profile personal
initd git-profile work
```

Behavior to preserve:

- validate the requested profile exists
- update `~/.gitconfig` to point at the selected managed profile
- reject unsupported profile names
- verify the final symlink
- print clear logs

Keep `scripts/git-profile.sh` available until the TypeScript command has matching tests.

## Phase 4: Port `cleanup`

Port `scripts/cleanup.sh` next.

The new command should support:

```bash
initd cleanup
initd cleanup --dry-run
```

Behavior to preserve:

- remove only symlinks owned by `initd`
- leave unmanaged user files untouched
- leave unrelated symlinks untouched
- remove safe empty directories only when appropriate
- support dry-run logging without making changes

This command should be tested with temporary home directories before it is used against a real home directory.

## Phase 5: Port `link`

Port `scripts/link.sh` after `cleanup`.

The new command should support:

```bash
initd link
```

Behavior to preserve:

- install managed links for Git, Kitty, mise, Neovim, and Zsh
- back up unmanaged conflicts to `~/.config/initd-backups/<timestamp>/`
- fold existing directories that contain only expected initd-owned links
- migrate legacy links and loader files
- set the default Git profile when needed
- verify every final link points to the expected source

This is the most important command to keep behavior-compatible with the current Bash implementation.

## Phase 6: Convert behavior tests

Mirror the coverage from `scripts/test-install-behavior.sh` in Vitest.

Recommended tests:

- clean link install
- backup unmanaged configs
- Git profile switching
- cleanup of managed links
- cleanup preserves unmanaged files
- directory folding
- legacy link migration

Tests should create temporary home directories and pass those paths into the TypeScript helpers. They should not mutate the real developer home directory.

Keep the Bash behavior test until TypeScript tests cover the same behavior.

## Phase 7: Port `brewinstall`

Port `scripts/brewinstall.sh` after the core filesystem commands.

The new command should support package additions such as:

```bash
initd brewinstall ripgrep
initd brewinstall --cask docker-desktop
```

Behavior to preserve:

- validate inputs
- detect formulae and casks when needed
- update `platforms/darwin/Brewfile`
- keep the Brewfile tidy
- run `brew bundle`
- show clear logs

TypeScript can own Brewfile editing and validation while still calling `brew` for Homebrew operations.

## Phase 8: Port macOS bootstrap last

Port `platforms/darwin/bootstrap.sh` only after the smaller commands are stable.

The new command should support:

```bash
initd bootstrap
initd bootstrap --platform darwin
```

Behavior to preserve:

- check Xcode Command Line Tools
- install or verify Homebrew
- run `brew bundle`
- handle Docker Desktop carefully
- install or refresh Oh My Zsh
- trust and install mise-managed runtimes
- run `initd link`
- verify final managed paths

This phase has the most host-specific behavior, so it should be migrated last.

## Bash compatibility strategy

Keep `bootstrap.sh` as a tiny compatibility entrypoint.

Its long-term job should be:

1. find the repo root
2. ensure a usable Node runtime exists
3. run the built TypeScript CLI
4. print a clear error if Node is unavailable

Example final shape:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v node >/dev/null 2>&1; then
  exec node "${ROOT_DIR}/dist/cli.js" bootstrap "$@"
fi

echo "Node is required before the TypeScript initd CLI can run."
echo "Install Node with Homebrew, mise, or use the Docker development environment."
exit 1
```

Individual Bash scripts can later become wrappers around the TypeScript CLI, then be removed if compatibility is no longer needed.

## Docker development environment

Add Docker for repeatable Node development and tests.

Example `Dockerfile`:

```dockerfile
FROM node:22-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends git bash ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["bash"]
```

Example usage:

```bash
docker build -t initd-node .
docker run --rm -it -v "$PWD:/workspace" initd-node npm install
docker run --rm -it -v "$PWD:/workspace" initd-node npm test
docker run --rm -it -v "$PWD:/workspace" initd-node npm run build
```

Use Docker for development, builds, and behavior tests. Run the real host bootstrap directly on macOS.

## Safe removal checklist

Before replacing a Bash script with TypeScript:

1. The TypeScript command preserves the Bash behavior.
2. Behavior tests cover the command.
3. The README points users to the new command.
4. The old Bash script either still works or wraps the TypeScript command.
5. The command has been tested with a temporary home directory when possible.
6. The command has clear logs and explicit failure messages.

Only remove old Bash implementation code after the TypeScript path has become the stable default.

