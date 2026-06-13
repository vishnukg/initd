# This file runs before Homebrew's vendor conf.d snippets.
#
# mise's Homebrew formula installs a vendor hook that runs `mise activate fish`
# for every new shell. We do activate (interactive shells only), but through
# the cached-init path in config.fish — the vendor hook would re-run it
# uncached and double-register the prompt hooks, and it doesn't exist on Linux
# (mise.run install), so config.fish is the one place activation happens.
set -gx MISE_FISH_AUTO_ACTIVATE 0

