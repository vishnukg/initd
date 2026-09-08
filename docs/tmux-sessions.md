# tmux sessions

Your prefix is **`C-a`** (Ctrl+a), not the default `C-b`.

---

## Mental model

```
tmux server (one per machine, invisible)
 └─ session "work"
 │   ├─ window 1: nvim
 │   └─ window 2: terminal
 └─ session "personal"
     └─ window 1: terminal
```

- **Session** — a named workspace. Survives closing your terminal. Switch between them like virtual desktops.
- **Window** — a tab inside a session.
- **Pane** — a split inside a window.

The session name shows in the bottom-left of your status bar in green. The
bottom-right shows the active pane's git branch (only inside a repository),
battery, and the active agent's model/usage pill.

---

## Auto-start: attach or create on terminal open

Add this to `shared/configs/fish/.config/fish/config.fish`, after the `fish_greeting` line:

```fish
# Auto-attach to tmux when opening a terminal
if status is-interactive && not set -q TMUX
    set -l default_session main
    if tmux has-session -t $default_session 2>/dev/null
        exec tmux attach -t $default_session
    else
        exec tmux new-session -s $default_session
    end
end
```

What this does:
- Only runs in interactive shells (not scripts).
- Does nothing if you're already inside tmux (`TMUX` is set).
- If a session named `main` exists → attaches to it (your work survives terminal restarts).
- Otherwise → creates a fresh session called `main`.

---

## Auto-attach on a remote server

The classic tmux use case: run tmux **on the server** so long-running work (builds, migrations, jobs) survives SSH disconnects. Detach with `C-a d`, drop the connection, and re-attach later from anywhere — the process never gets `SIGHUP`'d.

To make every interactive SSH login drop you straight into a persistent session, add this to the **server's** shell rc (`~/.bashrc` or `~/.zshrc` on the remote box):

```bash
# Auto-attach to tmux on interactive SSH login
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ] && command -v tmux >/dev/null; then
    tmux attach -t main 2>/dev/null || tmux new-session -s main
fi
```

What this does:
- Only runs over SSH (`SSH_CONNECTION` is set) and only in interactive shells not already inside tmux.
- Attaches to a session named `main` if it exists → your work survives across logins.
- Otherwise creates a fresh `main`.

Notes:
- **Nested tmux** (local tmux + server tmux): press `C-a C-a` to send the prefix to the *inner* (remote) tmux. The repo config already binds `C-a C-a` to `send-prefix`.
- A bare server shows plain default tmux unless you also deploy these dotfiles there — the durability works regardless of theme.

---

## Session commands

### From the command line (outside tmux)

| What | Command |
|---|---|
| Start a named session | `tmux new-session -s work` |
| List sessions | `tmux ls` |
| Attach to a session | `tmux attach -t work` |
| Attach to last session | `tmux attach` |
| Kill a session | `tmux kill-session -t work` |

### Inside tmux (keybindings)

| What | Keys |
|---|---|
| Session picker (tree view) | `C-a s` |
| Next session | `C-a )` |
| Previous session | `C-a (` |
| Rename current session | `C-a $` |
| Detach (leave session running) | `C-a d` |
| New session (command prompt) | `C-a :new-session` |

In the session picker (`C-a s`): navigate with `j/k`, expand/collapse with `Enter`, switch with `Enter` on a session, kill with `x`.

---

## Typical workflow

### One session per project

```
tmux new-session -s initd      # dotfiles work
tmux new-session -s myapp      # side project
```

Switch between them with `C-a s` to pick from the tree, or `C-a )` / `C-a (` to cycle.

### Naming convention

Short, lowercase, no spaces. Examples: `main`, `work`, `notes`, `srv`.

### Detach vs close

- **Detach** (`C-a d`) — session keeps running. SSH into a server, start a build, detach, come back later.
- **Closing the terminal** — with auto-attach set up, same effect as detach. Session persists until you reboot or `kill-session`.

---

## Quick reference card

```
Session
  tmux new-session -s NAME    create
  tmux attach -t NAME         attach
  tmux ls                     list
  C-a s                       session picker (tree view)
  C-a )  /  C-a (             next / prev session
  C-a $                       rename session
  C-a d                       detach

Window
  C-a c                       new window
  C-a Tab / BTab              next / prev window
  C-a ,                       rename window
  C-a X                       kill window

Pane
  C-a b                       split horizontal (below)
  C-a v                       split vertical
  C-a h/j/k/l                 navigate panes
  C-a z                       zoom pane (toggle fullscreen)
  C-a x                       kill pane
```

---

## Copy mode

tmux copy mode lets you scroll and copy from the terminal buffer — works everywhere (shell, Claude CLI, any TUI).

### Enter / exit

| What | Keys |
|---|---|
| Enter copy mode | `C-a [` |
| Exit copy mode | `q` or `Escape` |

### Navigate (vi keys — already enabled)

| What | Keys |
|---|---|
| Up / down | `k` / `j` |
| Half page up / down | `C-u` / `C-d` |
| Top / bottom of buffer | `g` / `G` |
| Search forward / backward | `/` / `?` |
| Next / previous match | `n` / `N` |

### Select and copy

1. `C-a [` — enter copy mode
2. Navigate to start of text
3. `v` — start selection
4. Move to end of selection
5. `y` — copy to system clipboard and exit copy mode

### Paste

`C-a ]` — paste (must be outside copy mode)

### When to use what

| Where | How to copy |
|---|---|
| Shell / Claude CLI / any TUI | `C-a [` → vi keys → `v` → `y` |
| Neovim | Use Neovim's own visual mode |
| Anywhere (mouse) | Hold `Option` + drag |

---

## Practice exercises

1. Open a new terminal → confirm it auto-attaches to `main` (after adding the fish snippet).
2. Create a second session: `tmux new-session -s scratch`
3. Open the picker: `C-a s` — you should see both sessions. Switch between them.
4. Rename: `C-a $`, type `work`, Enter. Watch the status bar update.
5. Detach: `C-a d`. Open a new terminal — you're back in `main`.
6. Clean up: `tmux kill-session -t work`.

## Agent status

The right-hand pill follows the focused pane's agent process. A background
watcher resolves process ancestry and open transcript files every three seconds.
When no agent pane is active it only checks tmux's pane list. Transcript reads
resume at the last complete newline; partial records are retried, and truncation
or file replacement resets the reader. The unchanged watcher command is a single
tmux status job; after code changes it exits so tmux starts the updated version.
It requires `node`, `ps`, and `lsof` (included on macOS; managed in Linux's package
list). If the process or session cannot be identified unambiguously, it shows
only the agent's icon, never another session's model. Icons are an amber robot
for Claude, a blue Copilot face for Copilot, and a coral Hubot for Codex. Agent
names are omitted from the pill. Claude and Codex both use
`model · percentage% · time until reset` (percentage is quota used); Copilot shows
its model, since this integration has no Copilot quota source.

Codex displays the latest `turn_context.model` in that process's open rollout.
This is the latest recorded turn model: a selection made while idle may not
appear until the next turn records it.
Codex also shows the latest recorded primary quota percentage used and
time until reset from its `token_count.rate_limits` data. This is account usage,
not context-window usage. The countdown updates between turns; an expired
snapshot is hidden until fresh data arrives.

Copilot uses `session.model_change` in its open session events file; auxiliary
model calls do not change the label.
If its events file is closed between writes, the watcher reads that process's
open `process-<timestamp>-<pid>.log` and follows its latest foreground-session
registration to the events file. This lookup is incremental and needs no
telemetry export. A model selection of `auto` appears as `auto`.
When a CLI does not keep its transcript open, the pill falls back to its agent
icon. Claude's status-line hook records its model and rate limits against the
owning process and its start time, with unique atomic cache writes. After
upgrading, Claude's model appears on its next hook invocation.

There are no cost estimates, usage-report subprocesses, or telemetry exports
needed for the pill. Pane caches expire after ten seconds if the watcher stops
updating them.
