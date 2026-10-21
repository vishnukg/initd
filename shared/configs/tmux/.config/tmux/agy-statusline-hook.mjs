#!/usr/bin/env node
import fs from 'node:fs';
import { hook } from './tmux.mjs';

try {
    hook(JSON.parse(fs.readFileSync(0, 'utf8')), 'agy');
} catch {
    // An empty status-line response leaves Antigravity's line blank, not broken.
}
