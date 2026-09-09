#!/usr/bin/env node
import { execFile, spawn } from 'node:child_process';
const run = (command, args) => new Promise(resolve => execFile(command, args, { encoding: 'utf8' }, (_, stdout) => resolve(stdout || '')));
const choose = (prompt, options) => new Promise(resolve => {
    const child = spawn('rofi', ['-dmenu', '-i', '-p', prompt], { stdio: ['pipe', 'pipe', 'ignore'] });
    child.stdin.end(options.join('\n'));
    let output = '';
    child.stdout.on('data', chunk => { output += chunk; });
    child.on('close', () => resolve(output.trim()));
});
const notify = message => spawn('notify-send', ['-t', '2500', '󰡨  Docker', message], { stdio: 'ignore' });
const containers = await run('docker', ['ps', '--format', '{{.Names}}\t{{.Status}}']);
if (!containers.trim()) { notify('No running containers'); process.exit(0); }
const selected = (await choose('docker', containers.trim().split('\n'))).split('\t')[0];
if (!selected) process.exit(0);
const action = await choose(selected, ['logs', 'shell', 'restart', 'stop']);
if (action === 'logs') spawn('kitty', ['docker', 'logs', '-f', '--tail', '200', selected], { detached: true, stdio: 'ignore' }).unref();
if (action === 'shell') spawn('kitty', ['docker', 'exec', '-it', selected, 'sh'], { detached: true, stdio: 'ignore' }).unref();
if (action === 'restart' || action === 'stop') {
    await run('docker', [action, selected]);
    notify(`${action === 'restart' ? 'Restarted' : 'Stopped'} ${selected}`);
}
