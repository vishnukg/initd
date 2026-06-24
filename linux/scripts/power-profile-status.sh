#!/bin/sh
# Print the current power profile as an icon for the polybar power-profile module.

case "$(powerprofilesctl get 2>/dev/null)" in
  power-saver) printf '\n' ;;
  balanced)    printf '\n' ;;
  performance) printf '\n' ;;
  *)           printf '\n' ;;
esac
