import { test } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { refresh, createStatusPublisher } from '../../shared/configs/tmux/.config/tmux/tmux.mjs';
import { agentPill, claudeValue } from '../../shared/configs/tmux/.config/tmux/status-renderer.mjs';

// Decode the same argv framing tmux receives, for readable batch assertions.
function tmuxCommands(args) {
    const commands = [[]];
    for (const arg of args) {
        if (arg === ';') commands.push([]);
        else commands.at(-1).push(arg);
    }
    return commands;
}

for (const command of ['fish', 'constructor', 'toString', '__proto__']) {
    test(`agentPill does not style unrecognized command ${command}`, () => {
        // Arrange
        const paneCommand = command;

        // Act
        const rendered = agentPill(paneCommand);

        // Assert
        assert.equal(rendered, '');
    });
}

test('Claude can show its model without rate limits and strips tmux formatting', () => {
    // Arrange
    const plain = { model: { display_name: 'Sonnet' } };
    const withFormatting = { model: { display_name: '#[bg=red]\nSonnet' } };

    // Act
    const modelOnly = claudeValue(plain);
    const sanitized = claudeValue(withFormatting);

    // Assert
    assert.equal(modelOnly, 'Sonnet');
    assert.equal(sanitized, '[bg=red]Sonnet');
});

for (const { name, five, week, budget, expected } of [
    { name: 'near-tied quiet week keeps five-hour quota', five: [19, 20000], week: [21, 200000], expected: 'Opus 5 · 19% · 4h0m' },
    { name: 'fuller week above threshold escalates', five: [7, 20000], week: [62, 200000], expected: 'Opus 5 · 62% week · 2d6h' },
    { name: 'nearly exhausted five-hour quota wins', five: [95, 20000], week: [62, 200000], expected: 'Opus 5 · 95% · 4h0m' },
    { name: 'fuller budget escalates', budget: [88, 20000], five: [19, 20000], week: [21, 200000], expected: 'Opus 5 · 88% budget · 4h0m' },
    { name: 'quiet budget keeps five-hour quota', budget: [30, 20000], five: [19, 20000], expected: 'Opus 5 · 19% · 4h0m' },
    { name: 'week is shown without five-hour quota', week: [21, 200000], expected: 'Opus 5 · 21% week · 2d6h' },
    { name: 'expired five-hour quota is ignored', five: [99, 5000], week: [21, 200000], expected: 'Opus 5 · 21% week · 2d6h' },
    { name: 'negative usage is ignored', five: [-1, 20000], expected: 'Opus 5' },
    { name: 'nonnumeric usage is ignored', five: ['19', 20000], expected: 'Opus 5' },
]) {
    test(`Claude quota selection: ${name}`, () => {
        // Arrange
        const limit = values => values && { used_percentage: values[0], resets_at: values[1] };
        const data = { model: { display_name: 'Opus 5' }, rate_limits: {
            five_hour: limit(five), seven_day: limit(week), spend_limit: limit(budget),
        } };

        // Act
        const rendered = claudeValue(data, 5600);

        // Assert
        assert.equal(rendered, expected);
    });
}

test('discovery and publishing share a snapshot and recheck ownership each cycle', async () => {
    // Arrange
    const snapshot = [['%1', '1', '10', 'claude', '/repo', '1']];
    const records = new Map();
    const sent = [];
    let scans = 0;
    const commandsRun = [];
    const runCommand = async (command, args) => {
        commandsRun.push(args[0]);
        if (command === 'tmux' && args[0] === 'set-option') sent.push(...tmuxCommands(args));
        return '';
    };
    const io = {
        run: runCommand,
        processes: async () => { scans++; return []; },
        atomic: (file, value) => records.set(path.basename(file), value),
    };

    // Act
    const publish = createStatusPublisher(runCommand,
        (server, root) => records.get(`pane-${server}-${root}`), async () => '', () => {});
    for (let tick = 0; tick < 2; tick++) {
        await refresh(io, snapshot);
        await publish(undefined, snapshot);
    }

    // Assert
    assert.equal(scans, 2, 'ownership must not be cached across cycles');
    assert.match(records.get('pane-1-10'), /\nclaude\nclaude\n$/);
    assert.ok(sent.some(args => args.includes('@initd-agent') && args.at(-1) === 'claude'));

    // Act
    await refresh(io, []);
    await publish(undefined, []);

    // Assert
    assert.equal(scans, 2, 'an empty snapshot must not trigger discovery');
    assert.ok(!commandsRun.includes('list-panes'), 'the supplied snapshot needs no extra query');
});

test('publisher renders every pill and sends well-formed set-option commands', async () => {
    // Arrange
    const sent = [];
    const runCommand = async (command, args) => {
        if (command === 'tmux' && args[0] === 'list-panes') return '%1\t100\t200\tclaude\t/repo\t1\n';
        if (command === 'tmux' && args[0] === 'list-windows') return '@1 \n';
        if (command === 'tmux' && args[0] === 'list-sessions') return '';
        if (command === 'git' && args.includes('symbolic-ref')) return 'main\n';
        if (command === 'tmux') sent.push(args);
        return '';
    };
    const now = 1000;

    // Act
    const publish = createStatusPublisher(runCommand, () => `${now}\nclaude\nOpus 5 · 12%\n`, async () => '87%', () => {});
    await publish(now);

    // Assert
    // Every option change goes in one invocation, as a ';'-separated sequence.
    assert.equal(sent.length, 1);

    const commands = tmuxCommands(sent[0]);

    assert.ok(commands.length > 1);

    // tmux rejects an option change that does not name the set-option command.
    for (const args of commands) {
        assert.equal(args[0], 'set-option');
    }
    const option = name => commands.find(args => args.includes(name))?.at(-1) ?? '';

    assert.match(option('@initd-battery'), /87%/);
    assert.match(option('@initd-agent-pill'), /Opus 5 · 12%/);
    assert.match(option('@initd-git-pill'), /main/);
    assert.deepEqual(commands.find(args => args.includes('@initd-agent'))?.slice(0, 4), ['set-option', '-p', '-t', '%1']);
    assert.match(option('@emoji'), /\p{Emoji}/u);
});

test('a pane path of exactly ";" is escaped so it cannot split the command sequence', async () => {
    // Arrange
    let sent = [];
    const runCommand = async (command, args) => {
        if (command === 'tmux' && args[0] === 'list-panes') return '%1\t100\t200\tclaude\t;\t1\n';
        if (command === 'tmux' && args[0] === 'list-windows') return '@1 \n';
        if (command === 'tmux') sent = args;
        return '';
    };

    // Act
    await createStatusPublisher(runCommand, () => '', async () => '', () => {})(1000);

    // Assert
    const directory = sent[sent.indexOf('@initd-directory') + 1];

    assert.equal(directory, '\\;', 'a bare ; would start a new tmux command');

    const commands = tmuxCommands(sent);

    assert.equal(sent.filter(arg => arg === ';').length, commands.length - 1,
        'one separator between commands, none extra');
});

test('a tmux-allocated numeric session is renamed; a chosen name is left alone', async () => {
    // Arrange
    let sent = [];
    const runCommand = async (command, args) => {
        if (command === 'tmux' && args[0] === 'list-panes') return '%1\t100\t200\tclaude\t/repo\t1\n';
        if (command === 'tmux' && args[0] === 'list-windows') return '@1 \n';
        if (command === 'tmux' && args[0] === 'list-sessions') return '$0 nova\n$1 1\n$2 2\n$3 notes\n';
        if (command === 'tmux') sent = args;
        return '';
    };

    // Act
    await createStatusPublisher(runCommand, () => '', async () => '', () => {})(1000);

    // Assert
    const commands = tmuxCommands(sent);
    const renames = commands.filter(args => args[0] === 'rename-session');

    // "nova" is already taken and "notes" was chosen by hand, so only the two
    // numeric sessions are renamed - each to a distinct still-free name.
    assert.deepEqual(renames, [['rename-session', '-t', '$1', 'vega'],
        ['rename-session', '-t', '$2', 'io']]);
});

test('session renaming stops when every name is taken rather than reusing one', async () => {
    // Arrange
    let sent = [];
    const taken = ['nova', 'vega', 'io', 'sol', 'luna', 'mars',
        'lyra', 'titan', 'pluto', 'orion'];
    const runCommand = async (command, args) => {
        if (command === 'tmux' && args[0] === 'list-panes') return '%1\t100\t200\tclaude\t/repo\t1\n';
        if (command === 'tmux' && args[0] === 'list-windows') return '@1 \n';
        if (command === 'tmux' && args[0] === 'list-sessions') {
            return taken.map((name, index) => `$${index} ${name}`).join('\n') + `\n$${taken.length} ${taken.length}\n`;
        }
        if (command === 'tmux') sent = args;
        return '';
    };

    // Act
    await createStatusPublisher(runCommand, () => '', async () => '', () => {})(1000);

    // Assert
    assert.ok(!sent.includes('rename-session'), 'a duplicate name would be rejected by tmux');
});

test('session names containing spaces are preserved in full', async () => {
    // Arrange
    let sent = [];

    // Act
    const publish = createStatusPublisher(async (command, args) => {
        if (args[0] === 'list-panes') return '%1\t100\t200\tfish\t/repo\t1\n';
        if (args[0] === 'list-sessions') return '$0 123 notes\n$1 nova work\n$2 2\n';
        if (command === 'tmux' && args[0] === 'set-option') sent = args;
        return '';
    }, () => '', async () => '', () => {});
    await publish(1000);

    // Assert
    const renames = tmuxCommands(sent).filter(args => args[0] === 'rename-session');

    // Assert
    assert.deepEqual(renames, [['rename-session', '-t', '$2', 'nova']]);
});

test('publisher skips unchanged writes, caches Git, and refreshes new directories immediately', async () => {
    // Arrange
    const calls = [];
    let directory = '/repo';
    let branch = 'main';
    const runCommand = async (command, args) => {
        calls.push([command, args[0]]);
        if (command === 'git') return branch;
        if (args[0] === 'list-panes') return `%1\t100\t200\tfish\t${directory}\t1\n%2\t100\t201\tfish\t${directory}\t0\n`;
        return '';
    };

    // Act
    const publish = createStatusPublisher(runCommand, () => '', async () => '', () => {});
    await publish(1000);

    // Arrange
    calls.length = 0;

    // Act
    await publish(1000.5);

    // Assert
    assert.deepEqual(calls, [['tmux', 'list-panes']]);

    // Arrange
    branch = 'feature';
    calls.length = 0;

    // Act
    await publish(1003);

    // Assert
    assert.equal(calls.filter(([cmd]) => cmd === 'git').length, 1, 'shared directory queried once');
    assert.ok(calls.some(([, action]) => action === 'set-option'));
    assert.ok(!calls.some(([, action]) => action === 'list-sessions'));

    // Arrange
    directory = '/new';
    calls.length = 0;

    // Act
    await publish(1003.5);

    // Assert
    assert.equal(calls.filter(([cmd]) => cmd === 'git').length, 1);

    // Arrange
    calls.length = 0;

    // Act
    await publish(1030);

    // Assert
    assert.ok(calls.some(([, action]) => action === 'list-windows'));
    assert.ok(calls.some(([, action]) => action === 'list-sessions'));
});

test('publisher retries option changes after a failed tmux batch', async () => {
    // Arrange
    let attempts = 0;

    // Act
    const publish = createStatusPublisher(async (command, args) => {
        if (args[0] === 'list-panes') return '%1\t100\t200\tfish\t/repo\t1\n';
        if (args[0] === 'set-option' && ++attempts === 1) throw new Error('server unavailable');
        return '';
    }, () => '', async () => '', () => {});
    const operation = publish(1000);

    // Assert
    await assert.rejects(operation, /server unavailable/);

    // Act
    await publish(1000.5);

    // Assert
    assert.equal(attempts, 2);
});
