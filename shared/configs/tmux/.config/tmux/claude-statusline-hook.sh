#!/usr/bin/env bash
# Claude Code's own statusLine hook (configured in ~/.claude/settings.json),
# not something tmux invokes directly - it lives here because its only
# purpose is feeding the same cache file agent-usage.sh reads for the
# Claude pill (shared/configs/tmux/.config/tmux/claude-usage). Replaces an
# earlier ccusage-based polling daemon (claude-usage-daemon.sh, since
# deleted) that copilot-usage-daemon.sh and codex-usage-daemon.sh still
# use the same shape of, for those two.
#
# Why this instead of ccusage: Claude Code pipes a `rate_limits` object on
# every invocation - server-authoritative usage straight from Anthropic's
# API responses (`five_hour.used_percentage`, `.resets_at`; also
# `seven_day` and, behind a spend-limited gateway, `spend_limit`), not a
# percentage inferred from parsing local transcripts the way ccusage's
# 5-hour "block" is. It's also event-driven (fires on every assistant
# message, /compact, mode changes, and automatically when a window's
# resets_at passes), plus the refreshInterval set in settings.json so the
# time-left figure keeps ticking down between events - no local log
# parsing at all, the data arrives on stdin already computed.
#
# `rate_limits` is absent for non-Pro/Max accounts and before the first API
# response in a session; when it's missing this writes an empty cache, so
# the tmux pill just doesn't appear - same as any other "nothing to show".
#
# Fable gets no special-casing: Anthropic's docs say Fable "can" bill to a
# separate usage-credits balance "depending on your plan and seat tier",
# with no documented way to tell which applies short of checking `/model`
# for a "Requires usage credits" label by hand - and even that balance has
# no scriptable source anywhere (confirmed: not in the statusLine JSON,
# only the interactive `/usage-credits` command). Deliberately not worth
# routing around: this just shows the same rate_limits.five_hour figure
# for Fable as every other model, accurate on plans where Fable draws from
# the standard limit, a known-approximate reading otherwise.
#
# stdout here becomes Claude Code's OWN in-app status line (the row above
# its footer), not just tmux's - configuring any custom statusLine also
# hides the footer's keyboard hints (`esc to interrupt` etc.), so this
# still prints something useful there rather than leaving it blank.
#
# Copilot and Codex have no equivalent hook - they stay on
# copilot-usage-daemon.sh / codex-usage-daemon.sh's ccusage polling.
cache_dir="$HOME/.cache/initd-tmux"
cache="$cache_dir/claude-usage"
mkdir -p "$cache_dir"

cache_tmp="${cache}.tmp"
export CACHE_TMP="$cache_tmp"
node -e '
    let d;
    try { d = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch { process.exit(0); }

    const model = (d.model && d.model.display_name) || "claude";
    const ctxPct = d.context_window && d.context_window.used_percentage != null
        ? Math.round(d.context_window.used_percentage) + "% ctx"
        : null;

    const five = d.rate_limits && d.rate_limits.five_hour;
    let tmuxValue = model;
    let statusLine = "[" + model + "]";
    if (ctxPct) statusLine += " " + ctxPct;

    if (five && five.used_percentage != null && five.resets_at) {
        const secsLeft = Math.max(0, five.resets_at - Date.now() / 1000);
        const minsLeft = Math.round(secsLeft / 60);
        const h = Math.floor(minsLeft / 60);
        const m = minsLeft % 60;
        const pct = Math.round(five.used_percentage);

        tmuxValue = model + " · " + h + "h" + m + "m · " + pct + "%";
        statusLine += " · " + pct + "% 5h limit";
    }

    require("fs").writeFileSync(process.env.CACHE_TMP, tmuxValue);
    process.stdout.write(statusLine);
' 2>/dev/null

# Atomic write so agent-usage.sh never reads a half-written file.
[[ -f "$cache_tmp" ]] && mv "$cache_tmp" "$cache"
