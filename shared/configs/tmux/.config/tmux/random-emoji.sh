#!/usr/bin/env bash
# Assign a vegetarian food or produce emoji to each tmux window.
win_id="$1"
existing=$(tmux show-options -wqv -t "$win_id" @emoji 2>/dev/null)

# Span warm and cool colours while keeping the set to fruit, vegetables and
# coffee.
emojis=(🍎 🍏 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍒 🍑 🥭 🍍 🥝 🍅 🥑 🫛 🥦 🥬 🥒 🌶️ 🫑 🌽 🥕 🫒 ☕)

# Preserve an existing icon when it is already part of the curated set. This
# also migrates old meat-oriented or ambiguous icons on the next config reload.
for emoji in "${emojis[@]}"; do
    [[ "$existing" == "$emoji" ]] && exit 0
done

tmux set-option -wt "$win_id" @emoji "${emojis[RANDOM % ${#emojis[@]}]}"
