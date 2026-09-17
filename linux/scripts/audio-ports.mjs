#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// pactl's card ports are an object keyed by port name (not the sink-port array).
// https://github.com/pulseaudio/pulseaudio/blob/master/src/utils/pactl.c
export function parsePorts(cards, warn = () => {}) {
    if (!Array.isArray(cards)) throw new Error('Expected a pactl card array');
    const ports = Object.create(null);
    const seen = new Set();
    // A card carrying ports in some other shape means pactl's JSON changed
    // under us. Every lookup then fails open, which is right at runtime but
    // silent - so count those cards and say so rather than returning {} as if
    // the machine simply had no ports.
    let unrecognized = 0;
    for (const card of cards) {
        const shaped = card?.ports && typeof card.ports === 'object' && !Array.isArray(card.ports);
        if (!shaped) {
            if (card?.ports !== undefined) unrecognized += 1;
            continue;
        }
        for (const [key, port] of Object.entries(card.ports)) {
            // Quickshell joins endpoints by port token. Ambiguous tokens must
            // fail open rather than borrow another sound card's availability.
            const token = key.replace(/^\[(?:Out|In)\]\s+/, '');
            if (seen.has(token)) { delete ports[token]; continue; }
            seen.add(token);
            if (!token || !port || typeof port !== 'object') continue;
            const name = port.properties?.['device.product.name'];
            ports[token] = {
                attached: port.availability !== 'not available',
                name: typeof name === 'string' ? name : '',
            };
        }
    }
    if (unrecognized > 0 && Object.keys(ports).length === 0) {
        warn(`audio-ports: ${unrecognized} card(s) carry ports in an unrecognized shape; pactl's JSON format may have changed`);
    }
    return ports;
}

export function readPorts(run = execFileSync, warn = console.error) {
    const output = run('pactl', ['--format=json', 'list', 'cards'], {
        encoding: 'utf8', timeout: 5000, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024,
        env: { ...process.env, LC_ALL: 'C' }, stdio: ['ignore', 'pipe', 'pipe'],
    });
    return parsePorts(JSON.parse(output), warn);
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        console.log(JSON.stringify(readPorts()));
    } catch (error) {
        // Clear stale availability on failure; every unmapped endpoint stays visible.
        console.log('{}');
        console.error(`audio-ports: ${error.message}`);
        process.exitCode = 1;
    }
}
