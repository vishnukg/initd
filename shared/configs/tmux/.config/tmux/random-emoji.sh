#!/usr/bin/env bash
# Assign a fun, vegetarian food/drink emoji to each tmux window. No meat,
# fish, or alcohol; no emoji repeats across windows while options remain.
#
# Runs from the after-new-window hook, so it is on the path of every new tab:
# pure bash string tests only (an earlier version spawned grep once per emoji
# and cost ~47 ms of a ~60 ms window open), and two tmux round-trips.
win_id="$1"

# Mostly fruit, sweets and snacks, plus a few vegetables - kept unambiguously
# meat- and alcohol-free.
emojis=(🍎 🍏 🍐 🍊 🍋 🍉 🍇 🍓 🍒 🥭 🍍 🥝 🍅 🌽 🥕 ☕
        🍕 🍩 🍪 🎂 🧁 🍰 🥐 🥯 🥞 🧇 🍫 🍬 🍭 🍯 🥧 🍞 🧀 🥨 🍦 🍨 🍿 🍵 🧃 🧋 🍮)

# One call for both the target window's current icon and every icon in use.
# Lines are "<window_id> <emoji>"; the emoji field is empty when unset.
used=" "
existing=""
while read -r id emoji; do
    [[ "$id" == "$win_id" ]] && existing="$emoji"
    [[ -n "$emoji" ]] && used+="$emoji "
done < <(tmux list-windows -a -F '#{window_id} #{@emoji}' 2>/dev/null)

# Preserve an existing icon when it is already part of the curated set. This
# also migrates old meat-oriented or ambiguous icons on the next config reload.
if [[ -n "$existing" ]]; then
    for emoji in "${emojis[@]}"; do
        [[ "$existing" == "$emoji" ]] && exit 0
    done
fi

available=()
for emoji in "${emojis[@]}"; do
    [[ "$used" == *" $emoji "* ]] || available+=("$emoji")
done

# If every emoji is already in use, fall back to the full set rather than
# leaving a window without one.
[[ ${#available[@]} -eq 0 ]] && available=("${emojis[@]}")

tmux set-option -wt "$win_id" @emoji "${available[RANDOM % ${#available[@]}]}"
