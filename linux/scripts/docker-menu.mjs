#!/usr/bin/env node
import fs from 'node:fs';
import { execFile, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const run = (command, args) => new Promise((resolve, reject) => execFile(command, args, {
    encoding: 'utf8', timeout: 30000, killSignal: 'SIGKILL',
}, (error, stdout) => error ? reject(error) : resolve(stdout)));
const choose = (prompt, options) => new Promise((resolve, reject) => {
    const child = spawn('rofi', ['-dmenu', '-i', '-no-custom', '-p', prompt], { stdio: ['pipe', 'pipe', 'ignore'] });
    child.on('error', reject);
    child.stdin.on('error', error => { if (error.code !== 'EPIPE') reject(error); });
    child.stdin.end(options.join('\n'));
    let output = '';
    child.stdout.on('data', chunk => { output += chunk; });
    child.on('close', code => {
        if (code === 1) return resolve(''); // user cancelled
        if (code !== 0) return reject(new Error(`rofi exited ${code}`));
        resolve(output.trim());
    });
});
const notify = message => run('notify-send', ['-t', '2500', '󰡨  Docker', message]);
const launch = args => new Promise((resolve, reject) => {
    const child = spawn('kitty', args, { detached: true, stdio: 'ignore' });
    child.on('error', reject);
    child.on('spawn', () => { child.unref(); resolve(); });
});

export async function dockerMenu(io = { run, choose, notify, launch }) {
    try {
        const containers = await io.run('docker', ['ps', '--format', '{{.Names}}\t{{.Status}}']);
        if (!containers.trim()) { await io.notify('No running containers'); return true; }
        const options = containers.trim().split('\n');
        const row = await io.choose('docker', options);
        if (!row) return true;
        if (!options.includes(row)) throw new Error('Selected container is not in the list');
        const selected = row.split('\t')[0];
        const action = await io.choose(selected, ['logs', 'shell', 'restart', 'stop']);
        if (action === 'logs') await io.launch(['docker', 'logs', '-f', '--tail', '200', selected]);
        if (action === 'shell') await io.launch(['docker', 'exec', '-it', selected, 'sh']);
        if (action === 'restart' || action === 'stop') {
            await io.run('docker', [action, selected]);
            await io.notify(`${action === 'restart' ? 'Restarted' : 'Stopped'} ${selected}`);
        }
    } catch (error) {
        const message = `Docker action failed: ${error.message}`;
        try { await io.notify(message); }
        catch { console.error(message); }
        return false;
    }
    return true;
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    if (await dockerMenu() === false) process.exitCode = 1;
}
