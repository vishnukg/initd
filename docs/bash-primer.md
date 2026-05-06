# Bash primer for initd

This is a small reference for maintaining the Bash scripts in this repo. It focuses on the syntax and patterns used by `bootstrap.sh`, `platforms/darwin/*.sh`, and `scripts/*.sh`.

## How to read the scripts

Start with the `main` function near the bottom of each larger script. It usually reads like a checklist:

```bash
main() {
  trap cleanup EXIT

  ensure_xcode_clt
  ensure_homebrew
  prepare_brewfile
  brew bundle --file "${WORK_BREWFILE}"
}

main "$@"
```

Most of the detail lives in helper functions above `main`.

## Script header

Most scripts start like this:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

`#!/usr/bin/env bash` tells the system to run the file with Bash.

`set -euo pipefail` enables safer defaults:

| Option | Meaning |
|---|---|
| `-e` | Exit when a command fails. |
| `-u` | Error when using an unset variable. |
| `-o pipefail` | A pipeline fails if any command in it fails, not just the last command. |

## Entrypoints and arguments

Larger scripts end with:

```bash
main "$@"
```

This calls the `main` function and forwards all command-line arguments.

| Syntax | Meaning |
|---|---|
| `$@` | All arguments, preserving each argument separately when quoted as `"$@"`. |
| `$*` | All arguments as one string when quoted as `"$*"`. Used in logging to join a message. |
| `$#` | Number of arguments. |
| `$0` | Script name as invoked. |
| `$1`, `$2` | First and second arguments. |

The top-level `bootstrap.sh` uses `exec`:

```bash
exec "${ROOT_DIR}/platforms/darwin/bootstrap.sh"
```

`exec` replaces the current process with the macOS bootstrap script. That means the OS dispatcher does not keep running after handing off.

## Variables

Assign variables without spaces:

```bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_BREWFILE=""
```

`BASH_SOURCE[0]` is the path to the current script file. It is more reliable than `$0` when a file is sourced by another script.

Use variables with quotes:

```bash
printf '%s\n' "${ROOT_DIR}"
```

Quoting prevents paths with spaces from being split into multiple arguments.

## Command substitution

`$(...)` runs a command and captures its output:

```bash
OS="$(uname -s)"
target="$(readlink "${path}")"
```

Nested command substitution is common when resolving paths:

```bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

Read it from the inside out:

1. `dirname "${BASH_SOURCE[0]}"` finds the script directory.
2. `cd ...` moves there.
3. `pwd` prints the absolute path.
4. `ROOT_DIR=...` stores that path.

## Functions

Functions group reusable logic:

```bash
require_command() {
  local command_name="$1"
  local context="$2"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log_error "${command_name} is required ${context}."
    exit 1
  fi
}
```

Inside functions:

| Syntax | Meaning |
|---|---|
| `local name="value"` | Function-scoped variable. |
| `$1`, `$2` | First and second function arguments. |
| `return` | Leave the function. |
| `exit 1` | Stop the whole script with failure. |

## Conditionals

The repo mostly uses `[[ ... ]]` for checks:

```bash
if [[ -L "${path}" ]]; then
  log "Path is a symlink."
fi
```

Useful checks used here:

| Check | Meaning |
|---|---|
| `[[ -e "${path}" ]]` | Path exists. |
| `[[ -f "${path}" ]]` | Path is a regular file. |
| `[[ -d "${path}" ]]` | Path is a directory. |
| `[[ -L "${path}" ]]` | Path is a symlink. |
| `[[ -x "${path}" ]]` | Path exists and is executable. |
| `[[ -n "${value}" ]]` | String is not empty. |
| `[[ -z "${value}" ]]` | String is empty. |
| `[[ "${a}" == "${b}" ]]` | Strings are equal. |
| `[[ "${path}" == "${dir}/"* ]]` | String starts with `${dir}/`. |
| `[[ "${value}" =~ ^[0-9]+$ ]]` | String matches a regular expression. |

Use `!` to negate a command or condition:

```bash
if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew is missing."
fi
```

## Integer checks

The repo uses `(( ... ))` for numeric tests:

```bash
if (( DRY_RUN )); then
  log "Would remove ${path}"
fi

if (( verify_status != 0 )); then
  exit 1
fi
```

Use `[[ ... ]]` for strings and files. Use `(( ... ))` for numbers.

## Case statements

`case` is used when there are a few known string choices:

```bash
case "${OS}" in
  Darwin)
    exec "${ROOT_DIR}/platforms/darwin/bootstrap.sh"
    ;;
  Linux)
    log_warn "Linux support is planned but not implemented yet."
    exit 1
    ;;
  *)
    log_error "Unsupported operating system: ${OS}"
    exit 1
    ;;
esac
```

`*)` is the fallback branch.

Multiple patterns can share a branch:

```bash
case "${remote}" in
  "${OH_MY_ZSH_REPO}"|"git@github.com:ohmyzsh/ohmyzsh.git")
    return 0
    ;;
esac
```

## Loops

Loop over arrays:

```bash
for link in "${MANAGED_LINKS[@]}"; do
  remove_link "${link%%:*}" "${link#*:}" "managed symlink"
done
```

Loop over command-line arguments:

```bash
while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
  esac
  shift
done
```

`$#` is the number of remaining arguments. `shift` drops the first argument so the next one becomes `$1`.

Loop over files with globs:

```bash
for entry in "${target}"/* "${target}"/.[!.]* "${target}"/..?*; do
  if [[ ! -e "${entry}" && ! -L "${entry}" ]]; then
    continue
  fi
done
```

This checks normal files, dotfiles like `.gitignore`, and dotfiles with two or more characters. The guard skips unmatched glob patterns.

## Arrays

Arrays hold multiple values:

```bash
PACKAGES=(kitty mise nvim zsh)
```

Use all array values safely with:

```bash
"${PACKAGES[@]}"
```

This preserves each item as its own argument.

## String trimming

Some scripts store pairs as `left:right` and split them with parameter expansion:

```bash
path="${link%%:*}"
expected="${link#*:}"
```

| Syntax | Meaning |
|---|---|
| `${link%%:*}` | Remove the longest `:*` from the end. This keeps everything before the first colon. |
| `${link#*:}` | Remove the shortest `*:` from the start. This keeps everything after the first colon. |
| `${path#"${HOME}/"}` | Remove the `$HOME/` prefix if present. |
| `${0##*/}` | Keep only the script name from a path. |

## Heredocs

`scripts/cleanup.sh` uses a heredoc to print help text:

```bash
cat <<EOF
Usage: ${0##*/} [--dry-run]
EOF
```

Everything until the closing `EOF` is passed to `cat`.

## Default and required variable forms

The scripts use a few safer variable forms:

```bash
local stream="${4:-stdout}"
: "${BACKUP_ROOT:?BACKUP_ROOT must be set before calling backup_path}"
```

| Syntax | Meaning |
|---|---|
| `${4:-stdout}` | Use `$4` if set and non-empty, otherwise use `stdout`. |
| `${BACKUP_ROOT:?message}` | Fail with `message` if `BACKUP_ROOT` is unset or empty. |

The leading `:` is a no-op command. It is used here only to trigger the required-variable check.

## Redirection

The scripts redirect output to keep logs useful:

```bash
command -v brew >/dev/null 2>&1
```

| Syntax | Meaning |
|---|---|
| `>/dev/null` | Discard standard output. |
| `2>/dev/null` | Discard standard error. |
| `2>&1` | Send standard error to the same place as standard output. |
| `>&2` | Print to standard error. |

## Pipelines and fallbacks

Pipelines connect commands:

```bash
grep -v '^[[:space:]]*$' "${path}" || true
```

`|| true` means "do not fail the script if the previous command found nothing." This is important with `set -e`, because `grep` exits with failure when there are no matches.

Use `&&` when the next command should run only after success:

```bash
cd "${ROOT_DIR}" && pwd
```

Use command conditions directly when the exit status is what matters:

```bash
if git -C "${OH_MY_ZSH_DIR}" merge --ff-only --quiet '@{u}'; then
  return
fi
```

This runs the `then` branch only if the command succeeds.

## Subshells

Parentheses run commands in a subshell:

```bash
(
  cd "${ROOT_DIR}"
  mise install --yes
)
```

The `cd` only affects the subshell. After the block finishes, the parent script is still in its original directory.

## Traps and cleanup

Temporary files should be removed even when a script fails:

```bash
cleanup() {
  rm -f "${WORK_BREWFILE}"
}

trap cleanup EXIT
```

`trap cleanup EXIT` runs `cleanup` when the script exits for any reason.

## Sourcing helper files

`source` loads functions and variables from another file into the current script:

```bash
source "${ROOT_DIR}/scripts/logging.sh"
source "${ROOT_DIR}/scripts/fs.sh"
source "${ROOT_DIR}/scripts/paths.sh"
```

This is how scripts share `log`, `log_error`, `resolve_symlink_target`, `backup_path`, and the managed path lists.

## Logging helpers

The repo uses small wrappers instead of plain `echo`:

```bash
log "Starting initd bootstrap for macOS."
log_success "Managed symlinks verified."
log_warn "Backing up unmanaged ${path} -> ${backup}"
log_error "Managed path points to the wrong target: ${path}"
```

These helpers live in `scripts/logging.sh` and keep output consistent.

## Common commands used by this repo

| Command | Used for |
|---|---|
| `command -v name` | Check whether a command exists. |
| `readlink path` | Read where a symlink points. |
| `ln -s source target` | Create a symlink. |
| `ln -snf source target` | Replace a symlink safely. |
| `rm path` / `rm -f path` | Remove files or symlinks. |
| `mv source dest` | Move unmanaged configs into backups. |
| `mkdir -p dir` | Create a directory and parents if needed. |
| `mktemp` | Create a temporary file. |
| `grep` | Search or filter text. |
| `awk` | Filter one line out of the temporary Brewfile. |
| `brew bundle` | Install Homebrew packages from the Brewfile. |
| `mise trust` / `mise install` | Trust config and install runtimes. |

## How to safely change these scripts

1. Keep `main` readable. It should describe the flow at a high level.
2. Put reusable filesystem logic in `scripts/fs.sh`.
3. Put shared ownership paths in `scripts/paths.sh`.
4. Put logging changes in `scripts/logging.sh`.
5. Prefer small functions with names like `ensure_*`, `verify_*`, `remove_*`, and `prepare_*`.
6. Always quote variables unless you intentionally want word splitting.
7. Be careful with `rm`, `mv`, and symlink logic. Test with a temporary `HOME` first.

## Validation commands

Run syntax checks after edits:

```bash
bash -n bootstrap.sh platforms/darwin/bootstrap.sh platforms/darwin/macos.sh scripts/link.sh scripts/cleanup.sh scripts/git-profile.sh scripts/logging.sh scripts/fs.sh scripts/paths.sh scripts/test-install-behavior.sh
```

Check for whitespace errors:

```bash
git diff --check
```

Run behavior tests without touching your real home directory:

```bash
scripts/test-install-behavior.sh
```

The test script creates temporary homes and checks clean installs, unmanaged config backups, cleanup behavior, legacy-only cleanup, directory folding, and legacy migrations.

You can also test managed links manually with a temporary home:

```bash
tmp_home="$(mktemp -d)"
HOME="${tmp_home}" scripts/link.sh
rm -rf "${tmp_home}"
```

## When Bash feels confusing

Before rewriting in another language, try this:

1. Move complex repeated code into a helper function.
2. Give the function a plain-English name.
3. Add one comment explaining why the branch exists.
4. Add a temp-`HOME` behavior check for the case you changed.

That usually makes installer scripts easier to maintain while keeping the bootstrap dependency-free.
