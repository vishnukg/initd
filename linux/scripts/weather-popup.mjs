#!/usr/bin/env node
import { spawn } from 'node:child_process';
const url = 'https://wttr.in/?format=%l|%c+%C,+%t+(feels+%f)|%w+wind,+%h+humidity|%p+precipitation,+%m';
try {
    const response = await fetch(url, { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error('weather request failed');
    const lines = (await response.text()).split('|');
    const location = lines.shift() || 'Weather';
    const details = lines.join('\n');
    spawn('notify-send', ['-t', '8000', '-h', 'string:x-canonical-private-synchronous:weather', `  ${location}`, details], { stdio: 'ignore' });
    spawn('qs', ['ipc', 'call', 'bar', 'refreshWeather'], { stdio: 'ignore' });
} catch {
    spawn('notify-send', ['-t', '3000', 'Weather', 'wttr.in unreachable'], { stdio: 'ignore' });
}
