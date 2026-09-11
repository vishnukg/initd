# ── Homebrew (Apple Silicon) ──────────────────────────────────────────────────
if test -x /opt/homebrew/bin/brew
    set -gx HOMEBREW_PREFIX /opt/homebrew
    fish_add_path -g /opt/homebrew/bin /opt/homebrew/sbin
    # Trailing '' exports as a trailing colon, telling man to also search default paths.
    set -gx MANPATH /opt/homebrew/share/man $MANPATH ''
end

# ── PATH ──────────────────────────────────────────────────────────────────────
# Add managed paths together. -g avoids writing universal variables, but
# preserves existing fish_user_paths and their order. Removing a path here
# does not erase inherited or previously configured entries.
#
# Mise: hybrid setup (see docs/mise.md). Shims are the baseline PATH for
# every context (scripts, editors, non-interactive shells); interactive
# shells additionally run `mise activate` (deferred - see below),
# which puts the real binaries first so launches skip the shim hop and
# tools keep their own process name (e.g. tmux tabs show nvim, not mise).
#
# Do not add mise install dirs here (starship/zoxide used to be listed so
# the prompt would skip the shim). mise's hook-env treats install dirs it
# finds in the inherited PATH as already covered, leaves them out of the
# tool list it prepends, and moves them to the very END of PATH - behind
# the shims - so in every activated shell `zoxide` resolved to the shim
# and zoxide's PWD hook cost ~26 ms per cd instead of ~2.5 ms. Left to
# mise, both dirs land at the front of PATH on activation. starship never
# needed the entry: its init embeds the absolute binary path.
set -l initd_paths
for dir in ~/.local/share/mise/shims \
           ~/.dotnet/tools \
           ~/.local/bin
    test -d $dir; and set -a initd_paths $dir
end
# Guard the empty case: on a machine where none of these exist yet,
# fish_add_path with no arguments just fails.
test -n "$initd_paths"; and fish_add_path -g $initd_paths

# Environment overrides apply to scripts as well as interactive shells.
# Keep aliases, abbreviations and other interactive setup in local.fish.
if test -f $__fish_config_dir/local.env.fish
    source $__fish_config_dir/local.env.fish
end

# ── Interactive-only config ────────────────────────────────────────────────────
if not status is-interactive
    return
end

# ── Tmux auto-attach ──────────────────────────────────────────────────────────
# Decide and attach/create inside one synchronous tmux command queue. No
# shell-side list/check race or locks that could survive a failed client.
# With no target, attach prefers the most recently used detached session.
# tmux allocates a numeric name; tmux.mjs renames it from its own list on the
# after-new-session hook. Set INITD_TMUX_AUTO_ATTACH=0 to opt out.
if not set -q TMUX; and test "$INITD_TMUX_AUTO_ATTACH" != 0; \
        and isatty stdin; and isatty stdout; and command -q tmux
    command tmux start-server \; if-shell -F '#{S:#{?session_attached,,1}}' 'attach-session' 'new-session'
    # Close the terminal now that tmux is done. `exit` cannot do it: from a
    # sourced config.fish it only stops sourcing the rest of the file and leaves
    # an interactive shell sitting at a prompt, so killing the last tmux window
    # dropped back to Fish instead of closing kitty. Replacing the shell here,
    # rather than exec'ing tmux itself, keeps what the exec was avoiding: a
    # failed tmux command still leaves a usable shell.
    if test $status -eq 0
        exec true
    end
    echo 'initd: tmux could not attach; continuing in Fish.' >&2
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

# ── Tool init (zoxide, starship, mise) ──────────────────────────────────────
# Generate fresh init from the selected binary. No shared cache to race on,
# no shim-mtime invalidation, and no stale captured PATH. A failed generator
# must not have its partial output sourced.
function __initd_tool_init
    command -q $argv[1]; or return
    set -l script (command $argv)
    or return
    printf '%s\n' $script | source
end
__initd_tool_init zoxide init fish
__initd_tool_init starship init fish --print-full-init
# Interactive-only mise activation: prepends real tool bins to PATH via a
# prompt hook so shims are only the non-interactive fallback.
#
# Deferred to the first command rather than run at startup: activation's
# initial `mise hook-env` adds startup work but buys nothing until a command
# runs - the shims above
# already resolve every tool for the prompt itself. fish_preexec fires
# before the first typed command executes, so that command (and every
# prompt after it) sees the fully activated environment; only the empty
# first prompt is drawn without it.
function __initd_mise_activate --on-event fish_preexec
    functions -e __initd_mise_activate
    # No PWD hook. mise's activate script otherwise re-evaluates the whole
    # toolset on every directory change AND again at the next prompt, and the
    # prompt hook alone is enough: fish_prompt handlers run before the prompt
    # is drawn, so the environment is current by the time anything can be
    # typed. Node still switches versions identically on entering and
    # leaving a project. cd + prompt is ~30 ms on 54 tools, of which ~23 ms
    # is the hook-env run itself: mise does a full re-evaluation on every
    # directory change (it has to schedule its enter/leave hooks there), so
    # hook_env.cache_ttl and hook_env.chpwd_only cannot skip it - both were
    # measured at the same ~23 ms. A prompt in the same directory takes the
    # early-exit path, ~7 ms.
    set -g mise_fish_mode disable_arrow
    __initd_tool_init mise activate fish
end

# ── Local overrides (machine-specific, not committed) ─────────────────────────
if test -f $__fish_config_dir/local.fish
    source $__fish_config_dir/local.fish
end
