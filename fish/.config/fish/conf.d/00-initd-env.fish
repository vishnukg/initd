# This file runs before Homebrew's vendor conf.d snippets.
#
# mise's Homebrew formula installs a vendor hook that runs `mise activate fish`
# for every new shell. This config uses mise shims instead, which are added to
# PATH in config.fish, so the full activation hook is unnecessary startup work.
set -gx MISE_FISH_AUTO_ACTIVATE 0

