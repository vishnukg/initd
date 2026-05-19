#!/bin/bash
# Pre-generate the blurred lock image — run at login or after changing wallpaper

wallpaper=$(awk -F= '/^file=/{print $2; exit}' ~/.config/nitrogen/bg-saved.cfg 2>/dev/null)

[ -z "$wallpaper" ] || [ ! -f "$wallpaper" ] || ! command -v convert &>/dev/null && exit 0

res=$(xrandr | awk '/ connected primary/{print $4}' | cut -d'+' -f1)
[ -z "$res" ] && res=$(xrandr | awk '/ connected/{print $3}' | cut -d'+' -f1 | head -1)

mkdir -p ~/.cache
convert "$wallpaper" -resize "${res}^" -gravity center -extent "$res" \
    -blur 0x8 ~/.cache/lockscreen.png
