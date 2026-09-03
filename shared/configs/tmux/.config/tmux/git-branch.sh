#!/usr/bin/env bash
# Git branch pill for the tmux status line. Called every status redraw with
# the active pane's directory; prints a styled pill, or nothing outside a
# repository so the pill disappears rather than sitting empty.
#
# Branch only, deliberately: a dirty/ahead indicator needs `git status`, which
# walks the tree and can take hundreds of ms in a big repo — too much for a
# one-second status interval. symbolic-ref is a single file read (~1 ms) and
# handles worktrees and submodules; detached HEAD falls back to the short sha.
#
# Glyphs are written as UTF-8 octal escapes rather than literal characters:
# they are Private Use Area code points that editors and terminals happily
# drop, which turned this pill into a plain rectangle once already. Octal
# escapes also work in macOS's bash 3.2 printf, where \u does not.
#   \356\202\266  U+E0B6  nf-ple-left_half_circle_thick   (pill left cap)
#   \356\202\264  U+E0B4  nf-ple-right_half_circle_thick  (pill right cap)
#   \363\260\230\254  U+F062C  nf-md-source_branch         (branch icon; #4ec994 is the active-tab
#                     green; the name stays bold like the date pill's text)
dir="$1"
[[ -d "$dir" ]] || exit 0

branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)" ||
    branch="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)" || exit 0
[[ -n "$branch" ]] || exit 0

# Keep long feature-branch names from eating the status line.
max=28
(( ${#branch} > max )) && branch="${branch:0:max-1}…"

printf '#[fg=#111116,bg=default]\356\202\266#[fg=#4ec994,bg=#111116,bold]\363\260\230\254 #[fg=#9aa5ce]%s #[fg=#111116,bg=default]\356\202\264 ' "$branch"
