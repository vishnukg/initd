#!/usr/bin/env bash
# Window emojis and space-themed session names, run by the after-new-window and
# after-new-session hooks and on config load (tmux.conf). Plain bash and a few
# tmux calls: ~10ms, where the old node path took ~100ms per new window and
# scanned every process while an agent ran.
#
# - Every window whose @emoji is not in the pool gets one, unused across the
#   server while any remain; repeats are allowed once the pool is exhausted.
#   Existing windows keep their icon while it stays in the pool.
# - Every session tmux named with a bare number gets the first free name from
#   the list; names chosen by hand are left alone, and once every name is taken
#   the numbers stay rather than duplicating one (tmux would refuse anyway).
#
# Each entry is a complete emoji string, so variation selectors stay attached.
# No `set -u`: bash 3.2 (macOS, which runs hooks) treats "${empty[@]}" as unset.
emojis=('🧬' '🧪' '⚗️' '🔬' '🔭'
    '🧮' '📐' '🧩' '♾️' '🎲'
    '🚀' '🛸' '🛰️' '🪐' '☄️'
    '🦕' '🎮' '👾' '🤖' '💎' '🧲')
names=(nova vega io sol luna mars lyra titan pluto orion)

# in_list needle item... - whole-string match, so "nova work" is not "nova".
in_list() {
    local needle=$1 item
    shift
    for item in "$@"; do [ "$item" = "$needle" ] && return 0; done
    return 1
}

# Every change goes out as one tmux command sequence, like the watcher's batch.
commands=()
queue() {
    [ ${#commands[@]} -gt 0 ] && commands+=(';')
    commands+=("$@")
}

used=()
ids=()
current=()
tab=$'\t'
while IFS=$tab read -r id emoji; do
    ids+=("$id")
    current+=("$emoji")
    in_list "$emoji" "${emojis[@]}" && used+=("$emoji")
done < <(tmux list-windows -a -F "#{window_id}${tab}#{@emoji}")

i=0
while [ $i -lt ${#ids[@]} ]; do
    if ! in_list "${current[$i]}" "${emojis[@]}"; then
        free=()
        for emoji in "${emojis[@]}"; do
            in_list "$emoji" "${used[@]}" || free+=("$emoji")
        done
        [ ${#free[@]} -eq 0 ] && free=("${emojis[@]}")
        pick=${free[$((RANDOM % ${#free[@]}))]}
        used+=("$pick")
        queue set-option -w -t "${ids[$i]}" @emoji "$pick"
    fi
    i=$((i + 1))
done

taken=()
numbered=()
while IFS=$tab read -r id name; do
    taken+=("$name")
    case $name in ''|*[!0-9]*) ;; *) numbered+=("$id") ;; esac
done < <(tmux list-sessions -F "#{session_id}${tab}#{session_name}")

for id in "${numbered[@]}"; do
    free=
    for name in "${names[@]}"; do
        if ! in_list "$name" "${taken[@]}"; then free=$name; break; fi
    done
    [ -n "$free" ] || break
    taken+=("$free")
    queue rename-session -t "$id" "$free"
done

[ ${#commands[@]} -gt 0 ] && tmux "${commands[@]}" >/dev/null 2>&1
exit 0
