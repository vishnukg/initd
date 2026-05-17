# tmux and Neovim Workspaces

A visual guide to the overlapping words in tmux and Neovim.

The short version:

```text
tmux = terminal workspace manager
nvim = editor workspace manager
```

Use tmux for projects, shells, and long-running commands. Use Neovim for files, editing layouts, LSP, search, and code navigation.

---

## The Big Picture

```text
┌──────────────────────────────────────────────────────────────┐
│ tmux session: my-app                                         │
│                                                              │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐ │
│  │ tmux window 1 │  │ tmux window 2 │  │ tmux window 3 │ │
│  │ editor        │  │ server        │  │ tests         │ │
│  │                │  │                │  │                │ │
│  │  ┌──────────┐  │  │  ┌──────────┐  │  │  ┌──────────┐  │ │
│  │  │ pane     │  │  │  │ pane     │  │  │  │ pane     │  │ │
│  │  │ nvim     │  │  │  │ npm dev  │  │  │  │ tests    │  │ │
│  │  └──────────┘  │  │  └──────────┘  │  │  └──────────┘  │ │
│  └────────────────┘  └────────────────┘  └────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

Inside the `nvim` pane, Neovim has its own workspace:

```text
┌──────────────────────────────────────────────┐
│ nvim                                         │
│                                              │
│ buffers open in memory:                      │
│   1 app.ts                                   │
│   2 app.test.ts                              │
│   3 README.md                                │
│                                              │
│ visible nvim windows:                        │
│  ┌──────────────────┬─────────────────────┐ │
│  │ window           │ window              │ │
│  │ showing app.ts   │ showing app.test.ts │ │
│  └──────────────────┴─────────────────────┘ │
└──────────────────────────────────────────────┘
```

## tmux Concepts

```text
tmux server
└── session
    ├── window
    │   ├── pane
    │   └── pane
    └── window
        └── pane
```

### tmux Session

A persistent workspace. Usually one session per project.

```text
session: my-app
├── window 1: editor
├── window 2: server
├── window 3: tests
└── window 4: shell
```

Useful commands:

```sh
tmux new -s my-app
tmux attach -t my-app
tmux ls
```

### tmux Window

A tab inside a tmux session. Use it for a major task or process.

```text
tmux session: my-app

┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
│ 1: editor  │ │ 2: server  │ │ 3: tests   │ │ 4: git     │
└────────────┘ └────────────┘ └────────────┘ └────────────┘
```

Think of a tmux window as a terminal tab.

### tmux Pane

A split terminal inside a tmux window. Each pane usually runs one shell or one process.

```text
tmux window: server

┌───────────────────────────┬───────────────────────────┐
│ pane 1                    │ pane 2                    │
│ npm run dev               │ tail -f log/development   │
│                           │                           │
└───────────────────────────┴───────────────────────────┘
```

Use panes when you need to see multiple terminal processes at the same time.

## Neovim Concepts

```text
nvim
├── buffers
│   ├── app.ts
│   ├── app.test.ts
│   └── README.md
├── windows
│   ├── viewport showing one buffer
│   └── viewport showing another buffer
└── tabs
    └── saved layout of windows
```

### Neovim Buffer

A buffer is text loaded into memory. It is often a file, but it can also be scratch text, help text, a terminal buffer, or plugin output.

```text
buffers:

┌─────────────┐
│ app.ts      │  open in memory
├─────────────┤
│ app.test.ts │  open in memory
├─────────────┤
│ README.md   │  open in memory
└─────────────┘
```

A buffer can exist even when it is not visible.

Useful commands:

```vim
:ls
:b app.ts
:bn
:bp
:bd
```

### Neovim Window

A window is a viewport that shows a buffer.

```text
nvim screen

┌───────────────────────────┐
│ nvim window               │
│ showing buffer: app.ts    │
└───────────────────────────┘
```

One buffer can be shown in multiple windows:

```text
┌───────────────────────┬───────────────────────┐
│ nvim window           │ nvim window           │
│ showing app.ts line 1 │ showing app.ts line 80│
└───────────────────────┴───────────────────────┘
```

### Neovim Split

A split is the action/layout that creates more Neovim windows.

```text
before split:

┌───────────────────────────┐
│ app.ts                    │
└───────────────────────────┘

after vertical split:

┌──────────────┬────────────┐
│ app.ts       │ app.test.ts│
└──────────────┴────────────┘
```

Useful commands:

```vim
:split
:vsplit
<C-w>s
<C-w>v
<C-w>h
<C-w>j
<C-w>k
<C-w>l
```

### Neovim Tab

A Neovim tab is not a file tab. It is a layout of Neovim windows.

```text
nvim tabs:

┌───────────────────────────┐
│ tab 1: editing layout     │
│ ┌───────────┬───────────┐ │
│ │ app.ts    │ test.ts   │ │
│ └───────────┴───────────┘ │
└───────────────────────────┘

┌───────────────────────────┐
│ tab 2: docs layout        │
│ ┌───────────────────────┐ │
│ │ README.md             │ │
│ └───────────────────────┘ │
└───────────────────────────┘
```

For most workflows, use buffers for files and use tabs only when you need separate layouts.

## Same Words, Different Meaning

| Word | tmux meaning | Neovim meaning |
|---|---|---|
| session | Persistent terminal workspace | Usually not a core editing concept |
| window | Terminal tab inside a session | Viewport showing a buffer |
| pane | Split terminal inside a tmux window | Not a main Neovim term; people often mean window/split |
| split | Action that creates tmux panes | Action that creates Neovim windows |
| tab | Usually people mean tmux window | Layout containing Neovim windows |
| buffer | Not a tmux concept | Open text/file in memory |

## Nested Diagram

This is what is happening when you run Neovim inside tmux:

```text
tmux server
└── tmux session: my-app
    ├── tmux window 1: editor
    │   └── tmux pane 1
    │       └── nvim
    │           ├── buffer: app.ts
    │           ├── buffer: app.test.ts
    │           ├── buffer: README.md
    │           ├── nvim window showing app.ts
    │           └── nvim window showing app.test.ts
    ├── tmux window 2: server
    │   └── tmux pane 1
    │       └── npm run dev
    └── tmux window 3: tests
        └── tmux pane 1
            └── npm test -- --watch
```

## Practical Rules

Use tmux when the thing is a process:

| Goal | Use |
|---|---|
| Keep a dev server running | tmux window or pane |
| Run tests while editing | tmux window or pane |
| Watch logs | tmux window or pane |
| Open a second shell | tmux window or pane |
| Detach and come back later | tmux session |

Use Neovim when the thing is editing:

| Goal | Use |
|---|---|
| Open another file | Neovim buffer |
| See two files side by side | Neovim split/window |
| Jump around code | Neovim buffers, LSP, telescope/fzf |
| Compare implementation and test | Neovim vertical split |
| Keep a different editor layout | Neovim tab, rarely |

The simplest rule:

```text
Different command or long-running process? tmux.
Different file or editor view? nvim.
```

## Recommended Daily Layout

```text
tmux session: project-name

┌──────────────────────────────────────────────────────────────┐
│ window 1: nvim                                               │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ nvim buffers: many files                                 │ │
│ │ nvim windows: 1-3 visible editing views                  │ │
│ └──────────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────┤
│ window 2: server                                             │
│ npm run dev                                                  │
├──────────────────────────────────────────────────────────────┤
│ window 3: tests                                              │
│ npm test -- --watch                                          │
├──────────────────────────────────────────────────────────────┤
│ window 4: shell/git                                          │
│ git status, build commands, one-off commands                 │
└──────────────────────────────────────────────────────────────┘
```

Start simple:

```text
1 tmux session per project
3-4 tmux windows per session
1 Neovim instance in the editor window
many Neovim buffers
1-3 Neovim windows/splits visible at once
```

## Keybinding Namespaces

Keep each tool in its own keybinding space:

```text
Ctrl-a <key>    = tmux commands
\ <key>         = Neovim leader commands
Ctrl-w <key>    = Neovim window/split commands
```

Example:

```text
Ctrl-a c        tmux: new window
Ctrl-a s        tmux: horizontal split
Ctrl-a v        tmux: vertical split
Ctrl-a h/j/k/l  tmux: move between panes
Ctrl-a H/J/K/L  tmux: resize panes
Ctrl-a z        tmux: zoom pane

\ff             nvim: find file
\fg             nvim: live grep
Ctrl-w h/j/k/l  nvim: move between editor windows
```

The tmux config deliberately avoids global tmux bindings like `Alt-h/j/k/l`.
That keeps Neovim in control while editing. You only enter tmux's keyspace when
you press `Ctrl-a`.

One caveat: Vim/Neovim has a built-in `Ctrl-a` command to increment numbers. If
you need to send a literal `Ctrl-a` into Neovim or the shell, press:

```text
Ctrl-a Ctrl-a
```

This is usually a good tradeoff because `Ctrl-a` is easy to press, works
reliably in terminals, and keeps tmux commands away from Neovim's leader and
window mappings.
