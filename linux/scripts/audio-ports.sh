#!/usr/bin/env bash
# Prints one line per sound-card port: `<port>|<availability>|<display name>`.
#
# Quickshell's Pipewire service exposes nodes only -- no devices, no routes --
# so the two facts the audio menu needs about a port live somewhere QML cannot
# reach: whether anything is plugged into it, and the name the attached display
# reports (`device.product.name`, lifted from the monitor's ELD). Both hang off
# the card's port, and pactl is the shortest path to them.
#
# Availability is one of "available", "not available", or "availability
# unknown". Ports that cannot detect presence report unknown, so only an
# explicit "not available" means nothing is attached.
set -euo pipefail

LC_ALL=C pactl list cards | awk '
  function flush() {
    if (port != "")
      printf "%s|%s|%s\n", port, availability, product
    port = ""
    availability = ""
    product = ""
  }

  /\[Out\] |\[In\] / {
    flush()
    port = $2
    sub(/:$/, "", port)
    # The parenthesised tail ends with the availability, but it also carries an
    # "availability group:" entry further left -- so take what follows the
    # *last* comma rather than searching for the word itself.
    availability = $0
    sub(/\)[[:space:]]*$/, "", availability)
    sub(/^.*, /, "", availability)
    next
  }

  /device\.product\.name = / {
    if (port == "")
      next
    product = $0
    sub(/^[^=]*= "/, "", product)
    sub(/"$/, "", product)
  }

  END { flush() }
'
