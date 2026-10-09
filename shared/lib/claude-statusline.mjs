#!/usr/bin/env node
// Points Claude Code's statusLine hook at shared/configs/tmux's
// claude-statusline-hook.mjs, which is what feeds the Claude pill in the tmux
// status line with server-authoritative rate-limit data (see that script's
// header for why), and registers the hooks that drive agent-state.sh - the
// blocked/working/done dot on each tmux tab. Run standalone or from a platform bootstrap, AFTER link.sh so
// the hook's path already resolves through the ~/.config/tmux symlink.
//
// Not a MANAGED_LINKS symlink: ~/.claude/settings.json also holds
// user/machine-specific Claude Code settings (modelSettings, theme, ...) this
// repo has no business overwriting, so its keys are merged in place instead. Lives
// in shared/ rather than per-platform because ~/.claude sits at the same path
// under $HOME on macOS and Linux and nothing here is platform-specific.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sameFlatObject, updateJsonFile } from './json-file.mjs';

const STATUS_LINE = {
    type: 'command',
    command: '~/.config/tmux/claude-statusline-hook.mjs',
    refreshInterval: 60,
};

const AGENT_STATE = '~/.config/tmux/agent-state.sh';
// event -> [matcher, state]. "blocked" means the agent is waiting on you: a
// permission prompt, an MCP elicitation, or an AskUserQuestion; PostToolUse
// flips it back once you answer. idle_prompt only settles a turn that Esc
// interrupted, since Stop never fires for one (see agent-state.sh).
const AGENT_HOOKS = {
    // Not "compact": auto-compaction can land mid-turn, and clearing there
    // would blank a working agent until its next tool call.
    SessionStart: [['startup|resume|clear', 'clear']],
    UserPromptSubmit: [[null, 'working']],
    PreToolUse: [['AskUserQuestion', 'blocked']],
    PostToolUse: [[null, 'working']],
    PostToolUseFailure: [[null, 'working']],
    Notification: [
        ['permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input', 'blocked'],
        ['idle_prompt', 'settle'],
    ],
    Stop: [[null, 'done']],
    StopFailure: [[null, 'done']],
    SessionEnd: [[null, 'clear']],
};
const ours = hook => typeof hook?.command === 'string' && hook.command.startsWith(`${AGENT_STATE} `);

// The user's own hooks are left alone. Ours are recognised by command path,
// stripped from every event (so one dropped from AGENT_HOOKS is cleaned up
// too) and re-appended; returns whether that changed anything, so a re-run is
// not a write.
export function mergeAgentHooks(config) {
    const before = JSON.stringify(config.hooks ?? null);
    const hooks = config.hooks && typeof config.hooks === 'object' && !Array.isArray(config.hooks)
        ? config.hooks : {};
    for (const [event, groups] of Object.entries(hooks)) {
        if (!Array.isArray(groups)) continue;
        const kept = groups
            .map(group => Array.isArray(group?.hooks) ? { ...group, hooks: group.hooks.filter(hook => !ours(hook)) } : group)
            .filter(group => !Array.isArray(group?.hooks) || group.hooks.length);
        if (kept.length) hooks[event] = kept;
        else delete hooks[event];
    }
    for (const [event, entries] of Object.entries(AGENT_HOOKS)) {
        hooks[event] = [...(hooks[event] ?? []), ...entries.map(([matcher, state]) => ({
            ...(matcher ? { matcher } : {}),
            hooks: [{ type: 'command', command: `${AGENT_STATE} ${state}` }],
        }))];
    }
    config.hooks = hooks;
    return JSON.stringify(hooks) !== before;
}

export function configureStatusLine({
    file = path.join(process.env.HOME, '.claude/settings.json'),
    log = console.log,
} = {}) {
    const changed = updateJsonFile(file, config => {
        const hooksChanged = mergeAgentHooks(config);
        if (sameFlatObject(config.statusLine, STATUS_LINE)) return hooksChanged;
        config.statusLine = STATUS_LINE;
        return true;
    });
    log(`OK Claude Code statusLine and agent-state hooks ${changed ? 'configured' : 'already configured'} (${file}).`);
    return changed;
}

const filename = fileURLToPath(import.meta.url);
if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        configureStatusLine();
    } catch (error) {
        console.error(`ERR Failed to update Claude Code settings: ${error.message}`);
        process.exitCode = 1;
    }
}
