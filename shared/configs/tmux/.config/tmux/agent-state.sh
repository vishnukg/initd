#!/usr/bin/env bash
# Per-pane agent state for the tmux tabs, C-a a and C-a g.
#
#   agent-state.sh working|blocked|done|clear   Claude Code hooks (settings.json)
#   agent-state.sh settle                       idle_prompt hook: working -> done
#   agent-state.sh next <client> <pane>         C-a a: oldest blocked agent
#   agent-state.sh list                         rows for the C-a g picker
#   agent-state.sh pick                         C-a g: fzf over those rows
#
# State is two pane options, @agent-state and @agent-since (epoch seconds of the
# last transition). Every reader also requires #{pane_current_command} to be
# claude, so a pane whose agent crashed before SessionEnd shows nothing rather
# than a stale dot.
#
# Hooks inherit $TMUX/$TMUX_PANE from the claude process, so they address their
# own pane with no process walking; outside tmux they are a no-op. They must
# stay silent: UserPromptSubmit and SessionStart stdout becomes model context.
set -u

agent_filter='#{==:#{pane_current_command},claude}'

# True when you are looking at the pane right now: it is the active pane of its
# session's active window, and a client showing that session has terminal focus
# (tmux tracks it with focus-events on).
seen() {
    local where
    where=$(tmux display-message -p -t "$TMUX_PANE" '#{&&:#{pane_active},#{window_active}} #{session_id}' 2>/dev/null)
    [ "${where%% *}" = 1 ] || return 1
    tmux list-clients -F '#{session_id} #{client_flags}' 2>/dev/null |
        grep -q "^${where#* } .*focused"
}

# "done" means finished and not yet looked at. An agent that finishes in front
# of you has been looked at, so it goes straight to idle; one that finishes
# elsewhere keeps its check until the pane-focus-in hook in tmux.conf sees you
# arrive. (Plain if, not ;;& - hooks run macOS's bash 3.2.)
if [ "${1:-}" = done ] && [ -n "${TMUX_PANE:-}" ] && seen; then
    set -- clear
fi

case "${1:-}" in
    working|blocked|done)
        [ -n "${TMUX_PANE:-}" ] || exit 0
        # PostToolUse fires on every tool call; only a real transition moves
        # @agent-since, so "blocked for 5m" means five minutes.
        current=$(tmux display-message -p -t "$TMUX_PANE" '#{@agent-state}' 2>/dev/null)
        [ "$current" = "$1" ] && exit 0
        tmux set-option -p -t "$TMUX_PANE" @agent-state "$1" \; \
            set-option -p -t "$TMUX_PANE" @agent-since "$(date +%s)" >/dev/null 2>&1
        ;;
    settle)
        # Esc interrupts a turn without firing Stop, which would leave the pane
        # "working" forever. Claude's idle_prompt notification (~60s at the
        # prompt) settles it - but only from working, so it can never hide a
        # blocked agent.
        [ -n "${TMUX_PANE:-}" ] || exit 0
        current=$(tmux display-message -p -t "$TMUX_PANE" '#{@agent-state}' 2>/dev/null)
        [ "$current" = working ] && exec "$0" done
        ;;
    clear)
        [ -n "${TMUX_PANE:-}" ] || exit 0
        tmux set-option -pu -t "$TMUX_PANE" @agent-state \; \
            set-option -pu -t "$TMUX_PANE" @agent-since >/dev/null 2>&1
        ;;
    next)
        client=$2 here=$3
        target=$(tmux list-panes -a \
            -f "#{&&:${agent_filter},#{==:#{@agent-state},blocked}}" \
            -F '#{@agent-since} #{pane_id}' | sort -n | awk -v here="$here" '$2 != here { print $2; exit }')
        if [ -n "$target" ]; then
            tmux switch-client -c "$client" -t "$target"
        else
            tmux display-message -c "$client" 'No agent is waiting on you'
        fi
        ;;
    list)
        # blocked, then working, then done/idle; oldest transition first.
        # Tab-separated throughout: session and directory names may contain
        # spaces, which would shift every later column.
        now=$(date +%s)
        tab=$'\t'
        tmux list-panes -a -f "$agent_filter" \
            -F "#{?#{==:#{@agent-state},blocked},0,#{?#{==:#{@agent-state},working},1,2}}${tab}#{e|+:0,#{@agent-since}}${tab}#{pane_id}${tab}#{session_name}:#{window_index}${tab}#{?#{@agent-state},#{@agent-state},idle}${tab}#{b:pane_current_path}" |
            sort -t "$tab" -k1,1n -k2,2n |
            awk -F '\t' -v now="$now" '{
                age = $2 ? now - $2 : 0
                ago = age >= 3600 ? int(age / 3600) "h" : age >= 60 ? int(age / 60) "m" : age "s"
                # Same glyphs and truecolor hues as the tab dots in tmux.conf.
                dot = $5 == "blocked" ? "\033[1;38;2;247;118;142m\363\260\200\250" \
                    : $5 == "working" ? "\033[1;38;2;224;175;104m\363\260\224\237" \
                    : $5 == "done" ? "\033[1;38;2;78;201;148m\363\260\204\254" : "\033[38;2;114;113;105m·"
                printf "%s\t%s %-8s\033[0m %-12s \033[38;2;114;113;105m%-4s\033[0m %s\n", $3, dot, $5, $4, ($2 ? ago : ""), $6
            }'
        ;;
    pick)
        # No client argument: display-popup does not expand formats in its
        # command, so #{client_name} would arrive literally. Without -c,
        # switch-client picks the most recently active client - the one that
        # just pressed C-a g.
        rows=$("$0" list)
        if [ -z "$rows" ]; then
            printf '\n  \033[38;2;114;113;105mNo agents running.\033[0m'; read -r -s -n 1 -t 2; exit 0
        fi
        # The tmux.conf palette: text #9aa5ce, accent/selection #4ec994 on
        # #1c3a2e (the message bar), borders #1a1a22 (pane borders), muted
        # #727169. tmux draws the outer border, so fzf draws none.
        target=$(printf '%s\n' "$rows" | fzf --ansi --delimiter='\t' --with-nth=2 --no-sort \
            --reverse --no-scrollbar --bind=ctrl-n:down,ctrl-p:up --info=inline-right --prompt='❯ ' --pointer='▌' --gutter=' ' \
            --color='fg:#9aa5ce,bg:-1,hl:#bb9af7,fg+:#4ec994,bg+:#1c3a2e,hl+:#bb9af7,gutter:-1' \
            --color='query:#dcd7ba,prompt:#4ec994,pointer:#4ec994,info:#727169,spinner:#4ec994' \
            --color='border:#1a1a22,separator:#1a1a22,preview-border:#1a1a22,label:#727169' \
            --preview='tmux capture-pane -ep -t {1} | tail -n "$FZF_PREVIEW_LINES"' \
            --preview-window=down,65%,border-top | cut -f1)
        [ -n "$target" ] && tmux switch-client -t "$target"
        ;;
esac
exit 0
