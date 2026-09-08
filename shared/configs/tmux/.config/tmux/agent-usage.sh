#!/usr/bin/env bash
# Cheap formatter: caches are scoped to the tmux server and pane process.
cmd="$1"
case "$cmd" in
    claude) color='#e0af68'; icon='\363\260\232\251' ;; # nf-md-robot, F06A9
    copilot) color='#7aa2f7'; icon='\357\222\270' ;;     # nf-oct-copilot, F4B8
    codex) color='#f7768e'; icon='\357\221\267' ;;       # nf-oct-hubot, F477
    *) exit 0 ;;
esac
value="$cmd"
if [[ "$2" =~ ^[0-9]+$ && "$3" =~ ^[0-9]+$ ]]; then
    cache="$HOME/.cache/initd-tmux/pane-$2-$3"
    if [[ -r "$cache" ]]; then
        { read -r updated; read -r agent; read -r cached; } < "$cache"
        now=$(date +%s)
        if [[ "$updated" =~ ^[0-9]+$ && "$agent" == "$cmd" ]] && (( now >= updated && now - updated < 10 )); then
            value="${cached:-$cmd}"
        fi
    fi
fi
# The icon identifies the agent, including when session metadata is unavailable.
[[ "$value" == "$cmd" ]] && value=''
value="${value#"$cmd: "}"
value="${value#"$cmd · "}"
printf "#[fg=#111116,bg=default]\356\202\266#[fg=${color},bg=#111116,bold] %b #[fg=#9aa5ce]%s #[fg=#111116,bg=default]\356\202\264 " "$icon" "$value"
