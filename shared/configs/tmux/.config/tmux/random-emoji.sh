#!/usr/bin/env bash
# Assign a fun, vegetarian food/drink emoji to each tmux window. No meat,
# fish, or alcohol; no emoji repeats across windows while options remain.
win_id="$1"
existing=$(tmux show-options -wqv -t "$win_id" @emoji 2>/dev/null)

# Mostly fruit, sweets and snacks, plus a few vegetables - kept unambiguously
# meat- and alcohol-free.
emojis=(🍎 🍏 🍐 🍊 🍋 🍉 🍇 🍓 🍒 🥭 🍍 🥝 🍅 🌽 🥕 ☕
        🍕 🍩 🍪 🎂 🧁 🍰 🥐 🥯 🥞 🧇 🍫 🍬 🍭 🍯 🥧 🍞 🧀 🥨 🍦 🍨 🍿 🍵 🧃 🧋 🍮)

# Preserve an existing icon when it is already part of the curated set. This
# also migrates old meat-oriented or ambiguous icons on the next config reload.
for emoji in "${emojis[@]}"; do
    [[ "$existing" == "$emoji" ]] && exit 0
done

# Collect emoji already claimed by other windows so each pill stays unique.
used=$(tmux list-windows -a -F '#{@emoji}' 2>/dev/null)

available=()
for emoji in "${emojis[@]}"; do
    grep -qxF "$emoji" <<< "$used" || available+=("$emoji")
done

# If every emoji is already in use, fall back to the full set rather than
# leaving a window without one.
[[ ${#available[@]} -eq 0 ]] && available=("${emojis[@]}")

tmux set-option -wt "$win_id" @emoji "${available[RANDOM % ${#available[@]}]}"
