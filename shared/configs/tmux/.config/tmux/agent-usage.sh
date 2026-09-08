#!/usr/bin/env bash
# Agent usage pill for the tmux status line. One-shot dispatcher, like
# git-branch.sh: tmux substitutes the focused pane's foreground command
# into the argument fresh on every 1s redraw, so switching panes updates
# the pill immediately, and it vanishes for any pane not actively running
# `claude`, `copilot`, or `codex` - usage info for whatever else is running
# there wouldn't mean anything.
#
# Computing the usage data itself is too expensive to do here every 1s
# (ccusage parses local session transcripts) - copilot-usage-daemon.sh and
# codex-usage-daemon.sh, silent persistent background jobs started once via
# status-right exactly like battery.sh, each refresh their own cache file
# every 60s. The Claude cache file has a different writer entirely -
# claude-statusline-hook.sh, invoked by Claude Code itself as its
# statusLine hook, event-driven rather than polled. This script only reads
# whichever file applies; nothing here spawns ccusage or knows which
# mechanism filled which file.
#
# Glyph is a UTF-8 octal escape, matching git-branch.sh's reasoning: raw
# Private Use Area characters are dropped by some editors/terminals. Same
# icon for all three agents - color is what distinguishes them (amber/
# blue/coral), matching how the rest of this bar treats color as state,
# never decoration.
#   \363\260\232\251  U+F06A9  nf-md-robot
cmd="$1"
icon='\363\260\232\251'

cache_dir="$HOME/.cache/initd-tmux"

case "$cmd" in
    claude)
        cache="$cache_dir/claude-usage"
        color='#e0af68'
        ;;
    copilot)
        cache="$cache_dir/copilot-usage"
        color='#7aa2f7'
        ;;
    codex)
        cache="$cache_dir/codex-usage"
        color='#f7768e'
        ;;
    *)
        exit 0
        ;;
esac

value="$(cat "$cache" 2>/dev/null)"
[[ -n "$value" ]] || exit 0

printf "#[fg=#111116,bg=default]\356\202\266#[fg=${color},bg=#111116,bold] ${icon} #[fg=#9aa5ce]%s #[fg=#111116,bg=default]\356\202\264 " "$value"
