#!/usr/bin/env bash
# Background half of the Codex usage pill (see agent-usage.sh). Same
# silent-trailing-#()-job shape as battery.sh/copilot-usage-daemon.sh: tmux
# starts this once via status-right and keeps it alive across `C-a r`
# reloads, but its own stdout is unused - it only refreshes a cache file
# every 60s so agent-usage.sh stays a cheap per-redraw file read.
#
# `ccusage codex session` has no equivalent of Claude's 5-hour block or an
# "isActive" flag either (same shape as Copilot's report), so "current
# usage" here means the session with the most recent lastActivity - a
# reasonable proxy given this pill is only ever shown while a pane is
# actively running `codex` anyway. --offline uses ccusage's bundled price
# table instead of fetching one, but still computes costUSD and models.
#
# Unlike Copilot, Codex needs no OTel wrapper or other setup: its CLI
# (mise: aqua:openai/codex) already writes structured session logs under
# ~/.codex by default, which ccusage reads directly. Note the field names
# differ slightly from Copilot's report despite the identical shape:
# costUSD not totalCost, and models is an object keyed by model name, not
# an array. Node (already a mise tool) parses the JSON so this doesn't
# need jq, which Linux doesn't ship by default.
#
# $HOME, not $TMPDIR: see copilot-usage-daemon.sh's header for why.
cache_dir="$HOME/.cache/initd-tmux"
cache="$cache_dir/codex-usage"

refresh() {
    # Recreate on every cycle, not just at startup - see copilot-usage-daemon.sh.
    mkdir -p "$cache_dir"

    command -v ccusage >/dev/null 2>&1 && command -v node >/dev/null 2>&1 || { : > "$cache"; return; }

    # No --since bound here - see copilot-usage-daemon.sh's comment for why
    # (unlike Claude's 5h-block guarantee, "most recent session" has no
    # fixed staleness bound that's safe to assume).

    local value
    value="$(ccusage codex session --json --offline 2>/dev/null | node -e '
        let d;
        try { d = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch { process.exit(0); }
        const sessions = d.sessions || [];
        if (sessions.length === 0) process.exit(0);

        const latest = sessions.reduce((a, b) =>
            new Date(b.lastActivity) > new Date(a.lastActivity) ? b : a
        );

        const cost = (latest.costUSD || 0).toFixed(2);
        const models = Object.keys(latest.models || {}).join("+");

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
