#!/usr/bin/env node
import fs from 'node:fs';
import { hook } from './tmux.mjs';

try {
    hook(JSON.parse(fs.readFileSync(0, 'utf8')));
} catch {
    // Claude treats an empty status-line response as a valid fallback.
}
