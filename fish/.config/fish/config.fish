# ── Homebrew (Apple Silicon) ──────────────────────────────────────────────────
# brew shellenv outputs bash syntax — set vars directly instead of eval'ing
if test -x /opt/homebrew/bin/brew
    set -gx HOMEBREW_PREFIX /opt/homebrew
    set -gx HOMEBREW_CELLAR /opt/homebrew/Cellar
    set -gx HOMEBREW_REPOSITORY /opt/homebrew
    fish_add_path /opt/homebrew/bin /opt/homebrew/sbin
    set -gx MANPATH /opt/homebrew/share/man $MANPATH
    set -gx INFOPATH /opt/homebrew/share/info $INFOPATH
end

# ── PATH ──────────────────────────────────────────────────────────────────────
fish_add_path ~/.local/bin
fish_add_path ~/.dotnet/tools

# ── Mise (runs in all contexts so scripts get correct tool versions) ───────────
if command -q mise
    mise activate fish | source
end

# ── Interactive-only config ────────────────────────────────────────────────────
if not status is-interactive
    exit
end

# ── Greeting ──────────────────────────────────────────────────────────────────
set -g fish_greeting ""

# ── Theme ─────────────────────────────────────────────────────────────────────
fish_config theme choose nord

# ── Vi mode ───────────────────────────────────────────────────────────────────
fish_vi_key_bindings
# Restore Ctrl+A/E for line start/end in insert mode (ergonomic with vi mode)
bind -M insert \ca beginning-of-line
bind -M insert \ce end-of-line

# ── Aliases ───────────────────────────────────────────────────────────────────
alias vi nvim
alias vim nvim

# ── Git abbreviations ────────────────────────────────────────────────────────
abbr -a g    git
abbr -a ga   'git add'
abbr -a gaa  'git add --all'
abbr -a gapa 'git add --patch'
abbr -a gau  'git add --update'
abbr -a gb   'git branch'
abbr -a gba  'git branch --all'
abbr -a gbd  'git branch --delete'
abbr -a gbD  'git branch -D'
abbr -a gcb  'git checkout -b'
abbr -a gcm  'git checkout main'
abbr -a gca  'git commit -a'
abbr -a gco  'git checkout'
abbr -a gcp  'git cherry-pick'
abbr -a gd   'git diff'
abbr -a gds  'git diff --staged'
abbr -a gf   'git fetch'
abbr -a gfa  'git fetch --all --prune'
abbr -a gl   'git pull'
abbr -a gpr  'git pull --rebase'
abbr -a glg  'git log --stat'
abbr -a glog 'git log --oneline --decorate --graph'
abbr -a gm   'git merge'
abbr -a gp   'git push'
abbr -a gpf  'git push --force-with-lease'
abbr -a grb  'git rebase'
abbr -a grba 'git rebase --abort'
abbr -a grbc 'git rebase --continue'
abbr -a grbi 'git rebase --interactive'
abbr -a grhh 'git reset --hard HEAD'
abbr -a gss  'git status --short'
abbr -a gst  'git status'
abbr -a gsta 'git stash push'
abbr -a gstl 'git stash list'
abbr -a gstp 'git stash pop'
abbr -a gsw  'git switch'
abbr -a gswc 'git switch --create'

# ── Zoxide ────────────────────────────────────────────────────────────────────
if command -q zoxide
    zoxide init fish | source
end

# ── Starship ──────────────────────────────────────────────────────────────────
if command -q starship
    starship init fish | source
end
