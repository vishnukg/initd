# ── Homebrew (Apple Silicon) ──────────────────────────────────────────────────
if test -x /opt/homebrew/bin/brew
    set -gx HOMEBREW_PREFIX /opt/homebrew
    fish_add_path /opt/homebrew/bin /opt/homebrew/sbin
    # Trailing '' exports as a trailing colon, telling man to also search default paths.
    set -gx MANPATH /opt/homebrew/share/man $MANPATH ''
end

# ── PATH ──────────────────────────────────────────────────────────────────────
# One fish_add_path call, not one per directory: it is a function with
# argparse and dedupe logic (~0.6 ms per call), so five calls were ~3 ms of
# a ~50 ms startup. The list is in final PATH order, front first.
#
# Mise: hybrid setup (see docs/mise.md). Shims are the baseline PATH for
# every context (scripts, editors, non-interactive shells); interactive
# shells additionally run `mise activate` (cached, deferred - see below),
# which puts the real binaries first so launches skip the shim hop and
# tools keep their own process name (e.g. tmux tabs show nvim, not mise).
# starship and zoxide get their install dirs directly so the prompt never
# goes through a shim.
set -l initd_paths
for dir in ~/.local/share/mise/installs/zoxide/latest \
           ~/.local/share/mise/installs/starship/latest \
           ~/.local/share/mise/shims \
           ~/.dotnet/tools \
           ~/.local/bin
    test -d $dir; and set -a initd_paths $dir
end
fish_add_path $initd_paths

# ── Interactive-only config ────────────────────────────────────────────────────
if not status is-interactive
    return
end

# ── Tmux auto-attach ──────────────────────────────────────────────────────────
# One session per terminal window: reclaim the most recently used session that
# has no client attached, or start a fresh one. Simultaneous windows never
# mirror each other; reopening a window picks detached work back up.
if not set -q TMUX
    set -l detached (tmux list-sessions \
        -f '#{==:#{session_attached},0}' \
        -F '#{session_last_attached} #{session_name}' 2>/dev/null |
        sort -rn | head -n1 | string split -m1 -f2 ' ')
    if test -n "$detached"
        exec tmux attach -t "=$detached"
    else
        # Terse names instead of tmux's 0/1/2; first free one wins.
        for s in fox owl elk bee ant koi ram yak
            if not tmux has-session -t "=$s" 2>/dev/null
                exec tmux new-session -s $s
            end
        end
        exec tmux new-session
    end
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
# Fish's vi mode otherwise changes insert/replace modes to line/underline
# cursors. Keep the terminal cursor a steady block in every mode.
set -g fish_cursor_default block
set -g fish_cursor_insert block
set -g fish_cursor_replace_one block
set -g fish_cursor_replace block
set -g fish_cursor_visual block
set -g fish_cursor_external block
fish_vi_key_bindings
# Restore Ctrl+A/E for line start/end in insert mode (ergonomic with vi mode)
bind -M insert \ca beginning-of-line
bind -M insert \ce end-of-line

# ── Aliases ───────────────────────────────────────────────────────────────────
# Plain functions rather than `alias`: alias is itself a function that parses
# its argument and builds the same thing, at about twice the cost. --wraps
# keeps the target's completions.
function vi --wraps nvim; nvim $argv; end
function vim --wraps nvim; nvim $argv; end
function l --wraps ls; ls -la $argv; end
function ssh --wraps ssh; TERM=xterm-256color command ssh $argv; end

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

# ── Cached tool init (zoxide, starship, mise) ─────────────────────────────────
# Regenerate the cached init script only when the binary is newer than the
# cache. Extra arguments are passed through to the init command.
function __source_cached_init --argument-names tool subcmd
    set -q subcmd[1]; or set subcmd init
    command -q $tool; or return
    set -l cache ~/.cache/fish/{$tool}_{$subcmd}.fish
    if not test -f $cache; or test (command -v $tool) -nt $cache
        mkdir -p (dirname $cache)
        command $tool $subcmd fish $argv[3..] >$cache
    end
    source $cache
end
__source_cached_init zoxide
# --print-full-init: plain `starship init fish` emits a one-line stub that
# runs `starship init fish --print-full-init | psub` at every startup, so
# the "cache" was still spawning starship, mktemp, cat and rm on each new
# shell (~7 ms). The full init is the ~90-line script the stub would fetch.
__source_cached_init starship init --print-full-init
# Interactive-only mise activation: prepends real tool bins to PATH via a
# prompt hook so shims are only the non-interactive fallback.
#
# Deferred to the first command rather than run at startup: activation's
# initial `mise hook-env` is ~65 ms, two thirds of a new tab's startup, and
# it buys nothing until a command runs - the shims above already resolve
# every tool for the prompt itself. fish_preexec fires before the first
# typed command executes, so that command (and every prompt after it) sees
# the fully activated environment; only the empty first prompt is drawn
# without it.
function __initd_mise_activate --on-event fish_preexec
    functions -e __initd_mise_activate
    # No PWD hook. mise's activate script otherwise re-evaluates the whole
    # toolset on every directory change AND again at the next prompt, and the
    # prompt hook alone is enough: fish_prompt handlers run before the prompt
    # is drawn, so the environment is current by the time anything can be
    # typed. Measured on 56 tools: cd + prompt 147 ms -> 99 ms, with node
    # switching versions identically on entering and leaving a project. The
    # remaining ~88 ms is mise walking every tool (mostly npm dependency
    # trees, ~8,700 stats) even when it then emits nothing - mise's own cost,
    # unaffected by hook_env.cache_ttl, hook_env.chpwd_only or env_cache.
    set -g mise_fish_mode disable_arrow
    __source_cached_init mise activate
end

# ── Local overrides (machine-specific, not committed) ─────────────────────────
if test -f ~/.config/fish/local.fish
    source ~/.config/fish/local.fish
end
