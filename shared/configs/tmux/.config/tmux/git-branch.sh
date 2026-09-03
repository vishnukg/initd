#!/usr/bin/env bash
# Git branch pill for the tmux status line. Called every status redraw with
# the active pane's directory; prints a styled pill, or nothing outside a
# repository so the pill disappears rather than sitting empty.
#
# Branch only, deliberately: a dirty/ahead indicator needs `git status`, which
# walks the tree and can take hundreds of ms in a big repo — too much for a
# one-second status interval. symbolic-ref is a single file read (~1 ms) and
# handles worktrees and submodules; detached HEAD falls back to the short sha.
dir="$1"
[[ -d "$dir" ]] || exit 0

branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)" ||
    branch="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)" || exit 0
[[ -n "$branch" ]] || exit 0

# Keep long feature-branch names from eating the status line.
max=28
(( ${#branch} > max )) && branch="${branch:0:max-1}…"

printf '#[fg=#111116,bg=default]#[fg=#e0af68,bg=#111116,bold]  #[fg=#9aa5ce,nobold]%s #[fg=#111116,bg=default] ' "$branch"
