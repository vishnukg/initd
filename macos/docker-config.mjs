#!/usr/bin/env node
// The two Docker CLI settings this repo owns in ~/.docker/config.json: the
// osxkeychain credential helper, and Homebrew's cli-plugins directory so
// `docker compose` and `docker buildx` resolve from brew rather than needing
// Docker Desktop. It also clears the CLI hooks Docker Desktop leaves behind.
// macOS-only, hence living here rather than in shared/.
//
// Merged rather than written, because config.json also holds currentContext
// and any existing registry auths - see shared/lib/json-file.mjs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { updateJsonFile } from '../shared/lib/json-file.mjs';

const CREDS_STORE = 'osxkeychain';
const PLUGIN_DIR = '/opt/homebrew/lib/docker/cli-plugins';
// Docker Desktop's CLI hints: after these commands its bundled plugins (Gordon
// AI, Scout, debug, its compose hints) print suggestions. Without Desktop the
// plugins are gone and the hooks point at nothing. Only these keys are
// removed; any other plugin settings in the file are left alone.
const DESKTOP_HOOKED_PLUGINS = ['ai', 'compose', 'debug', 'scout'];
const DESKTOP_HINTS_PLUGIN = '-x-cli-hints';

function removeDesktopHooks(config) {
    let dirty = false;
    const plugins = config.plugins;
    if (plugins && typeof plugins === 'object' && !Array.isArray(plugins)) {
        for (const name of DESKTOP_HOOKED_PLUGINS) {
            const entry = plugins[name];
            if (entry && typeof entry === 'object' && 'hooks' in entry) {
                delete entry.hooks;
                if (Object.keys(entry).length === 0) delete plugins[name];
                dirty = true;
            }
        }
        if (DESKTOP_HINTS_PLUGIN in plugins) {
            delete plugins[DESKTOP_HINTS_PLUGIN];
            dirty = true;
        }
        if (Object.keys(plugins).length === 0) delete config.plugins;
    }
    // The switch that turns those hooks on.
    const features = config.features;
    if (features && typeof features === 'object' && 'hooks' in features) {
        delete features.hooks;
        if (Object.keys(features).length === 0) delete config.features;
        dirty = true;
    }
    return dirty;
}

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
        return removeDesktopHooks(config) || dirty;
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
