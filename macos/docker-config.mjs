#!/usr/bin/env node
// The two Docker CLI settings this repo owns in ~/.docker/config.json: the
// osxkeychain credential helper, and Homebrew's cli-plugins directory so
// `docker compose` and `docker buildx` resolve from brew rather than needing
// Docker Desktop. macOS-only, hence living here rather than in shared/.
//
// Merged rather than written, because config.json also holds currentContext,
// plugin hints and any existing registry auths - see shared/lib/json-file.mjs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { updateJsonFile } from '../shared/lib/json-file.mjs';

const CREDS_STORE = 'osxkeychain';
const PLUGIN_DIR = '/opt/homebrew/lib/docker/cli-plugins';

export function configureDocker({
    file = path.join(process.env.HOME, '.docker/config.json'),
    log = console.log,
} = {}) {
    const changed = updateJsonFile(file, config => {
        let dirty = false;
        if (config.credsStore !== CREDS_STORE) {
            config.credsStore = CREDS_STORE;
            dirty = true;
        }
        // Appended, never replaced: Docker Desktop and other installs register
        // their own plugin directories here, and dropping one would unhook its
        // plugins. A non-array value is treated as absent and normalised away.
        const dirs = Array.isArray(config.cliPluginsExtraDirs) ? config.cliPluginsExtraDirs : [];
        if (!dirs.includes(PLUGIN_DIR)) {
            config.cliPluginsExtraDirs = [...dirs, PLUGIN_DIR];
            dirty = true;
        }
        return dirty;
    });
    log(`OK Docker config ${changed ? 'updated' : 'already set'} (${CREDS_STORE} credsStore, brew CLI plugins dir).`);
    return changed;
}

const filename = fileURLToPath(import.meta.url);
if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        configureDocker();
    } catch (error) {
        console.error(`ERR Failed to update Docker config: ${error.message}`);
        process.exitCode = 1;
    }
}
