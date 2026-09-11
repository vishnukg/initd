#!/usr/bin/env node
import { execFile } from 'node:child_process';
// A missing notification/IPC tool emits an asynchronous error; the fetch
// try/catch cannot catch it. Bound these commands and report failures.
const run = (command, args) => execFile(command, args, { timeout: 5000 }, error => {
    if (error) console.error(`${command}: ${error.message}`);
});
const url = 'https://wttr.in/?format=%l|%c+%C,+%t+(feels+%f)|%w+wind,+%h+humidity|%p+precipitation,+%m';
try {
    const response = await fetch(url, { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error('weather request failed');
    const lines = (await response.text()).split('|');
    const location = lines.shift() || 'Weather';
    const details = lines.join('\n');
    run('notify-send', ['-t', '8000', '-h', 'string:x-canonical-private-synchronous:weather', `  ${location}`, details]);
    run('qs', ['ipc', 'call', 'bar', 'refreshWeather']);
} catch {
    run('notify-send', ['-t', '3000', 'Weather', 'wttr.in unreachable']);
}
