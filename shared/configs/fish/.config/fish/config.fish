# ── Homebrew (Apple Silicon) ──────────────────────────────────────────────────
if test -x /opt/homebrew/bin/brew
    set -gx HOMEBREW_PREFIX /opt/homebrew
    fish_add_path /opt/homebrew/bin /opt/homebrew/sbin
    # Trailing '' exports as a trailing colon, telling man to also search default paths.
    set -gx MANPATH /opt/homebrew/share/man $MANPATH ''
end

# ── PATH ──────────────────────────────────────────────────────────────────────
fish_add_path ~/.local/bin
if test -d ~/.dotnet/tools
    fish_add_path ~/.dotnet/tools
end

# ── Mise ──────────────────────────────────────────────────────────────────────
fish_add_path ~/.local/share/mise/shims
if test -d ~/.local/share/mise/installs/starship/latest
    fish_add_path ~/.local/share/mise/installs/starship/latest
end
if test -d ~/.local/share/mise/installs/zoxide/latest
    fish_add_path ~/.local/share/mise/installs/zoxide/latest
end

# ── Interactive-only config ────────────────────────────────────────────────────
if not status is-interactive
    exit
end

# ── Greeting ──────────────────────────────────────────────────────────────────
set -g fish_greeting ""

# ── Theme: Nord ───────────────────────────────────────────────────────────────
# Keep colors in config instead of running `fish_config theme choose nord` on
# every shell startup. `fish_config` is a setup command and does extra work.
set -g fish_color_normal --reset
set -g fish_color_autosuggestion 4c566a
set -g fish_color_cancel --reverse
set -g fish_color_command 88c0d0
set -g fish_color_comment 4c566a --italics
set -g fish_color_cwd 5e81ac
set -g fish_color_cwd_root bf616a
set -g fish_color_end 81a1c1
set -g fish_color_error bf616a
set -g fish_color_escape ebcb8b
set -g fish_color_history_current e5e9f0 --bold
set -g fish_color_host a3be8c
set -g fish_color_host_remote ebcb8b
set -g fish_color_keyword 81a1c1
set -g fish_color_operator 81a1c1
set -g fish_color_option 8fbcbb
set -g fish_color_param d8dee9
set -g fish_color_quote a3be8c
set -g fish_color_redirection b48ead --bold
set -g fish_color_search_match --background=434c5e --bold
set -g fish_color_selection d8dee9 --background=434c5e --bold
set -g fish_color_status bf616a
set -g fish_color_user a3be8c
set -g fish_color_valid_path --underline
set -g fish_pager_color_completion e5e9f0
set -g fish_pager_color_description ebcb8b --italics
set -g fish_pager_color_prefix --bold --underline
set -g fish_pager_color_progress 3b4252 --background=d08770 --bold
set -g fish_pager_color_selected_background --background=434c5e

# ── Vi mode ───────────────────────────────────────────────────────────────────
fish_vi_key_bindings
# Restore Ctrl+A/E for line start/end in insert mode (ergonomic with vi mode)
bind -M insert \ca beginning-of-line
bind -M insert \ce end-of-line

# ── Aliases ───────────────────────────────────────────────────────────────────
alias vi nvim
alias vim nvim
alias l 'ls -la'

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
    command zoxide init fish | source
end

# ── Starship ──────────────────────────────────────────────────────────────────
if command -q starship
    command starship init fish | source
end

# ── Local overrides (machine-specific, not committed) ─────────────────────────
if test -f ~/.config/fish/local.fish
    source ~/.config/fish/local.fish
end
