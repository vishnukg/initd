#!/usr/bin/env bash
# Background half of the Copilot usage pill (see agent-usage.sh). Same
# silent-trailing-#()-job shape as battery.sh: tmux starts this once via
# status-right and keeps it alive across `C-a r` reloads, but its own
# stdout is unused - it only refreshes a cache file every 60s so
# agent-usage.sh stays a cheap per-redraw file read.
#
# `ccusage copilot session` has no equivalent of Claude's 5-hour block or
# an "isActive" flag, so "current usage" here means the session with the
# most recent lastActivity - a reasonable proxy given this pill is only
# ever shown while a pane is actively running `copilot` anyway. --offline
# uses ccusage's bundled price table instead of fetching one, but still
# computes totalCost and modelsUsed.
#
# Requires Copilot CLI's OpenTelemetry file export, turned on by the
# `copilot` wrapper function in shared/configs/fish's config.fish - without
# it ccusage has no per-session cost data and this cache stays empty (pill
# just doesn't appear, same as any other "nothing to show"). Node (already
# a mise tool) parses the JSON so this doesn't need jq, which Linux doesn't
# ship by default.
#
# $HOME, not $TMPDIR: the tmux server keeps the environment it was started
# with, which can disagree with a pane's current shell about where $TMPDIR
# points (it's a per-login-session generated path on macOS) - agent-usage.sh
# reading a different directory than this job writes to would fail
# silently. $HOME is the one thing every context here agrees on.
cache_dir="$HOME/.cache/initd-tmux"
cache="$cache_dir/copilot-usage"

refresh() {
    # Recreate on every cycle, not just at startup: this is a long-lived
    # loop, and anything that clears $cache_dir out from under it (a stray
    # `rm -rf`, an OS temp/cache cleaner) would otherwise leave it writing
    # into a directory that no longer exists, forever, until the process is
    # restarted by hand.
    mkdir -p "$cache_dir"

    command -v ccusage >/dev/null 2>&1 && command -v node >/dev/null 2>&1 || { : > "$cache"; return; }

    # No --since bound on the scan: "most recent session" has no fixed
    # staleness guarantee the way Claude's 5h rate-limit window does (that
    # can never be more than 5h old, so bounding a scan to yesterday would
    # be provably safe there) - if this agent hasn't been used in days, the
    # real most recent session could be older than any fixed cutoff, and a
    # bound would make the daemon report nothing right when picking the
    # tool back up is exactly when you'd want to see it (verified: the
    # actual most recent Codex session on this machine was 3 days old, and
    # a 1-day bound found zero sessions).

    local value
    value="$(ccusage copilot session --json --offline 2>/dev/null | node -e '
        let d;
        try { d = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch { process.exit(0); }
        const sessions = d.sessions || [];
        if (sessions.length === 0) process.exit(0);

        const latest = sessions.reduce((a, b) =>
            new Date(b.lastActivity) > new Date(a.lastActivity) ? b : a
        );

        const cost = (latest.totalCost || 0).toFixed(2);

        // Copilot is multi-provider (gpt-*, claude-*, ...), so keep the
        // full name here - unlike the Claude pill, "claude-" is not implied.
        const models = (latest.modelsUsed || []).join("+");

        process.stdout.write((models ? models + " · " : "") + "$" + cost);
    ')"

    # Atomic write so agent-usage.sh never reads a half-written file.
    printf '%s' "$value" > "${cache}.tmp" && mv "${cache}.tmp" "$cache"
}

while true; do
    refresh
    printf '\n'
    sleep 60
done
