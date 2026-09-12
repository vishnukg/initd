#!/usr/bin/env node
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const unit = 'night-light.service';
const usage = 'Usage: night-light-toggle.mjs [toggle|on|off|auto]';

export function scheduledState(hour) {
    if (!Number.isInteger(hour) || hour < 0 || hour > 23) throw new Error('Night-light hour must be between 0 and 23');
    return hour >= 19 || hour < 7 ? 'on' : 'off';
}

// The service is the state. Wait for stray gammastep processes to exit before
// starting it: two gamma controllers can leave Hyprland unable to change gamma.
export async function nightLight(args = [], {
    run = spawnSync, wait = sleep,
    hour = Number(process.env.NIGHT_LIGHT_HOUR || new Date().getHours()),
} = {}) {
    if (args.length > 1 || !['toggle', 'on', 'off', 'auto'].includes(args[0] || 'toggle')) throw new Error(usage);
    const command = (name, values, allowed = [0]) => {
        const result = run(name, values, { stdio: 'ignore', timeout: 15000, killSignal: 'SIGKILL' });
        if (result.error) throw result.error;
        if (!allowed.includes(result.status)) throw new Error(`${name} failed (${result.signal || result.status})`);
        return result.status;
    };
    const active = () => command('systemctl', ['--user', 'is-active', '--quiet', unit], [0, 3, 4]) === 0;
    const stray = () => command('pgrep', ['-x', 'gammastep'], [0, 1]) === 0;
    const on = () => active() || stray();
    const bestEffort = (name, values) => {
        try { command(name, values); } catch { /* Optional notification/IPC tool. */ }
    };
    const notify = message => bestEffort('notify-send', [
        '-t', '1500', '-h', 'string:x-canonical-private-synchronous:nightlight', 'Night light', message,
    ]);
    const stopStrays = async () => {
        if (active() || !stray()) return;
        command('pkill', ['-x', 'gammastep'], [0, 1]);
        for (let attempt = 0; attempt < 80; attempt++) {
            if (!stray()) return;
            await wait(100);
        }
        if (stray()) throw new Error('gammastep did not stop; refusing to start a second gamma controller');
    };

    try {
        let wanted = args[0] || 'toggle';
        if (wanted === 'auto') wanted = scheduledState(hour);
        if (wanted === 'toggle') wanted = on() ? 'off' : 'on';
        if (wanted === 'on') {
            if (!active()) {
                await stopStrays();
                command('systemctl', ['--user', 'start', unit]);
                // ConditionEnvironment may skip the service with exit status 0.
                if (active()) notify('On (4500K)');
            }
        } else if (on()) {
            command('systemctl', ['--user', 'stop', unit]);
            await stopStrays();
            if (on()) throw new Error('Night light is still active after stopping');
            notify('Off');
        }
    } finally {
        bestEffort('qs', ['ipc', 'call', 'bar', 'refreshNightLight']);
    }
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    nightLight(process.argv.slice(2)).catch(error => {
        console.error(`night-light: ${error.message}`);
        process.exitCode = error.message === usage ? 2 : 1;
    });
}
