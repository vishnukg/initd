#!/usr/bin/env bash
# Assign a random emoji to a tmux window option (@emoji) if not already set.
win_id="$1"
existing=$(tmux show-options -wqv -t "$win_id" @emoji 2>/dev/null)
[[ -n "$existing" ]] && exit 0
emojis=(🚀 🔥 ⚡ 🍄 🎃 🍕 🐱 ☕ 🃏 💎 🎯 🌊 🐺 🎸 🌙 ⭐ 💫 🪄 🦊 🐉 🎲 🍦 🦅 🐙)
tmux set-option -wt "$win_id" @emoji "${emojis[RANDOM % ${#emojis[@]}]}"
