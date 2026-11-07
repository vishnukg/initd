// The bar's pure presentation logic, extracted from shell.qml and AudioMenu.qml
// so it is reachable from `node --test`. Glyphs stay as \u escapes: they are
// Private Use Area code points that editors and terminals silently drop.
import { test } from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import {
    clockMinutes, isNight, weatherIcon, weatherCelsius, weatherColor,
    loadColor, deviceKind, kindRank, KIND_ORDER,
    cpuTimes, cpuPercent, memoryUsage, batteryPercent,
    bluetoothDeviceIcon, compareBluetoothDevices, trayRole, backlightPercent,
    isInternalOutput, externalBrightness, switcherOrder, switcherStep,
    diskUsage, formatGiB,
} from '../../linux/configs/quickshell/bar-logic.mjs';
import * as BarLogic from '../../linux/configs/quickshell/bar-logic.mjs';

const THUNDER = '\u{f0593}', THUNDER_WET = '\u{f067e}', ICE = '\u{f0592}', FOG = '\u{f0591}';
const MIST = '\u{f0f30}', SLEET = '\u{f067f}', BLIZZARD = '\u{f0f36}', SNOW = '\u{f0598}';
const SNOW_PATCHY = '\u{f0f35}', RAIN_HEAVY = '\u{f0596}', RAIN = '\u{f0597}';
const RAIN_PATCHY = '\u{f0f33}', PARTLY_DAY = '\u{f0595}', PARTLY_NIGHT = '\u{f0f31}';
const CLOUD = '\u{f0590}', SUN = '\u{f0599}', MOON = '\u{f0594}', UNKNOWN = '\u{f0f2f}';

for (const { name, condition, night = false, expected } of [
    // The severity order is the specification. Each case below is a pair that
    // an out-of-order test chain would resolve to the wrong glyph.
    { name: 'freezing fog is fog, not sleet', condition: 'Freezing fog', expected: FOG },
    { name: 'plain sleet is sleet', condition: 'Light sleet showers', expected: SLEET },
    { name: 'freezing drizzle is sleet, not rain', condition: 'Patchy freezing drizzle possible', expected: SLEET },
    { name: 'thunder with rain outranks rain', condition: 'Moderate or heavy rain with thunder', expected: THUNDER_WET },
    { name: 'thunder with snow outranks snow', condition: 'Patchy light snow with thunder', expected: THUNDER_WET },
    { name: 'dry thunder has its own glyph', condition: 'Thundery outbreaks possible', expected: THUNDER },
    { name: 'ice pellets outrank rain showers', condition: 'Light showers of ice pellets', expected: ICE },
    { name: 'hail is ice', condition: 'Hail', expected: ICE },
    { name: 'blizzard outranks snow', condition: 'Blizzard', expected: BLIZZARD },
    { name: 'heavy snow outranks snow', condition: 'Heavy snow', expected: BLIZZARD },
    { name: 'patchy snow is distinguished', condition: 'Patchy light snow', expected: SNOW_PATCHY },
    { name: 'plain snow', condition: 'Light snow', expected: SNOW },
    { name: 'torrential rain outranks rain', condition: 'Torrential rain shower', expected: RAIN_HEAVY },
    { name: 'patchy rain is distinguished', condition: 'Patchy light rain', expected: RAIN_PATCHY },
    { name: 'drizzle counts as rain', condition: 'Light drizzle', expected: RAIN },
    { name: 'mist is not fog', condition: 'Mist', expected: MIST },
    { name: 'haze is mist', condition: 'Haze', expected: MIST },
    { name: 'overcast is cloud', condition: 'Overcast', expected: CLOUD },
    { name: 'sunny is never a moon', condition: 'Sunny', night: true, expected: SUN },
    { name: 'clear by day is a sun', condition: 'Clear', expected: SUN },
    { name: 'clear by night is a moon', condition: 'Clear', night: true, expected: MOON },
    { name: 'partly cloudy by day', condition: 'Partly cloudy', expected: PARTLY_DAY },
    { name: 'partly cloudy by night', condition: 'Partly cloudy', night: true, expected: PARTLY_NIGHT },
    // wttr.in can fail or return a name this vocabulary does not cover.
    { name: 'an unknown condition falls back', condition: 'Dust whirls', expected: UNKNOWN },
    { name: 'an empty condition falls back', condition: '', expected: UNKNOWN },
    { name: 'a missing condition falls back', condition: undefined, expected: UNKNOWN },
]) {
    test(`weather icon: ${name}`, () => {
        // Arrange
        const reading = condition;

        // Act
        const glyph = weatherIcon(reading, night);

        // Assert
        assert.equal(glyph, expected);
    });
}

for (const { name, temperature, expected } of [
    { name: 'Celsius is read as-is', temperature: '+18°C', expected: 18 },
    { name: 'a negative reading keeps its sign', temperature: '-3°C', expected: -3 },
    { name: 'Fahrenheit is converted', temperature: '72°F', expected: (72 - 32) * 5 / 9 },
    { name: 'freezing Fahrenheit is zero Celsius', temperature: '32°F', expected: 0 },
    { name: 'a fractional reading survives', temperature: '18.5°C', expected: 18.5 },
    { name: 'a reading with no number is unusable', temperature: 'n/a', expected: NaN },
    { name: 'an empty reading is unusable', temperature: '', expected: NaN },
]) {
    test(`weather temperature: ${name}`, () => {
        // Arrange
        const reading = temperature;

        // Act
        const celsius = weatherCelsius(reading);

        // Assert
        assert.deepEqual(celsius, expected);
    });
}

const NEUTRAL = '#e8eaf0';
for (const { name, celsius, expected } of [
    // The mild band is flat on purpose: colour means state, not decoration.
    { name: 'the cold edge of mild is flat', celsius: 12, expected: NEUTRAL },
    { name: 'the warm edge of mild is flat', celsius: 25, expected: NEUTRAL },
    { name: 'just below mild is cool', celsius: 11.9, expected: '#8fd8e8' },
    { name: 'just above mild is warm', celsius: 25.1, expected: '#e8b87a' },
    { name: 'freezing is the deepest blue', celsius: 0, expected: '#6fa8e0' },
    { name: 'below freezing stays the deepest blue', celsius: -40, expected: '#6fa8e0' },
    { name: 'cold', celsius: 5.9, expected: '#8fb7e8' },
    { name: 'hot', celsius: 34.9, expected: '#e89a8f' },
    { name: 'the top of the ramp is red', celsius: 35, expected: '#e0788a' },
    { name: 'an unreadable temperature is flat', celsius: NaN, expected: NEUTRAL },
]) {
    test(`weather colour: ${name}`, () => {
        // Arrange
        const reading = celsius;

        // Act
        const colour = weatherColor(reading);

        // Assert
        assert.equal(colour, expected);
    });
}

for (const { name, reading, expected } of [
    { name: 'idle is flat', reading: '0', expected: NEUTRAL },
    { name: 'below the amber threshold is flat', reading: '69', expected: NEUTRAL },
    { name: 'the amber threshold is inclusive', reading: '70', expected: '#e8b87a' },
    { name: 'below the red threshold stays amber', reading: '89', expected: '#e8b87a' },
    { name: 'the red threshold is inclusive', reading: '90', expected: '#e0788a' },
    { name: 'a percent suffix is tolerated', reading: '95%', expected: '#e0788a' },
    { name: 'an unreadable value is flat', reading: '--%', expected: NEUTRAL },
]) {
    test(`load colour: ${name}`, () => {
        // Arrange
        const value = reading;

        // Act
        const colour = loadColor(value);

        // Assert
        assert.equal(colour, expected);
    });
}

for (const { name, value, expected } of [
    { name: 'a 24-hour time', value: '06:12:00', expected: 372 },
    { name: 'a morning 12-hour time', value: '06:12:00 AM', expected: 372 },
    { name: 'an afternoon 12-hour time', value: '07:05:00 PM', expected: 1145 },
    { name: 'midnight in 12-hour form is zero', value: '12:00:00 AM', expected: 0 },
    { name: 'noon in 12-hour form is not midnight', value: '12:00:00 PM', expected: 720 },
    { name: 'an unparseable time is rejected', value: 'unknown', expected: -1 },
    { name: 'an empty time is rejected', value: '', expected: -1 },
]) {
    test(`clock parsing: ${name}`, () => {
        // Arrange
        const text = value;

        // Act
        const minutes = clockMinutes(text);

        // Assert
        assert.equal(minutes, expected);
    });
}

for (const { name, minutes, expected } of [
    { name: 'before sunrise is night', minutes: 5 * 60, expected: true },
    { name: 'sunrise itself is day', minutes: 6 * 60 + 12, expected: false },
    { name: 'midday is day', minutes: 12 * 60, expected: false },
    { name: 'sunset itself is night', minutes: 19 * 60 + 5, expected: true },
    { name: 'after sunset is night', minutes: 23 * 60, expected: true },
]) {
    test(`day and night: ${name}`, () => {
        // Arrange
        const sunrise = '06:12:00';
        const sunset = '19:05:00';

        // Act
        const night = isNight(sunrise, sunset, minutes);

        // Assert
        assert.equal(night, expected);
    });
}

test('an unusable sunrise or sunset is treated as daytime', () => {
    // Arrange
    // wttr.in was unreachable, so the day/night variants have nothing to go on:
    // a sun is the safer default, since a moon at noon reads as broken.
    const midnight = 0;

    // Act
    const missingBoth = isNight('', '', midnight);
    const missingSunset = isNight('06:12:00', '', midnight);
    const missingSunrise = isNight('', '19:05:00', midnight);

    // Assert
    assert.equal(missingBoth, false);
    assert.equal(missingSunset, false);
    assert.equal(missingSunrise, false);
});

for (const { name, node, expected } of [
    // HDMI and USB endpoints are ALSA devices too, so each of these would come
    // back as "Built-in" if the generic alsa_ test ran before them.
    { name: 'an HDMI sink is not built-in', node: 'alsa_output.pci-0000_00_1f.3.HiFi__HDMI1__sink', expected: 'HDMI' },
    { name: 'a DisplayPort sink is HDMI', node: 'alsa_output.pci-0000_00_1f.3.HiFi__displayport1__sink', expected: 'HDMI' },
    { name: 'a USB headset is not built-in', node: 'alsa_output.usb-Generic_Headset-00.analog-stereo', expected: 'USB' },
    { name: 'the laptop speaker is built-in', node: 'alsa_output.pci-0000_00_1f.3.HiFi__Speaker__sink', expected: 'Built-in' },
    { name: 'a paired headset is Bluetooth', node: 'bluez_output.AA_BB_CC_DD_EE_FF.1', expected: 'Bluetooth' },
    // Bluetooth and AirPlay are checked first, so a name carrying both tokens
    // resolves by connection type rather than by transport.
    { name: 'a Bluetooth name mentioning USB is still Bluetooth', node: 'bluez_output.usb_headset', expected: 'Bluetooth' },
    { name: 'an AirPlay target is AirPlay', node: 'raop_output.Apple-TV.local', expected: 'AirPlay' },
    { name: 'a filter chain is virtual', node: 'effect_input.eq6', expected: 'Virtual' },
    { name: 'an unnamed node is virtual', node: '', expected: 'Virtual' },
    { name: 'a missing name is virtual', node: undefined, expected: 'Virtual' },
    { name: 'classification ignores case', node: 'ALSA_OUTPUT.USB-Headset', expected: 'USB' },
]) {
    test(`device kind: ${name}`, () => {
        // Arrange
        const nodeName = node;

        // Act
        const kind = deviceKind(nodeName);

        // Assert
        assert.equal(kind, expected);
    });
}

test('endpoints are ranked so the built-in speaker keeps a stable position', () => {
    // Arrange
    // Rank order is what stops rows jumping around as devices come and go.
    const names = [
        'raop_output.Apple-TV.local',
        'alsa_output.pci-0000_00_1f.3.HiFi__HDMI1__sink',
        'effect_input.eq6',
        'alsa_output.pci-0000_00_1f.3.HiFi__Speaker__sink',
        'bluez_output.AA_BB_CC_DD_EE_FF.1',
        'alsa_output.usb-Generic_Headset-00.analog-stereo',
    ];

    // Act
    const ordered = [...names].sort((a, b) => kindRank(a) - kindRank(b)).map(deviceKind);

    // Assert
    assert.deepEqual(ordered, KIND_ORDER);
    assert.deepEqual(KIND_ORDER, ['Built-in', 'USB', 'HDMI', 'Bluetooth', 'AirPlay', 'Virtual']);
});

test('every BarLogic call site in the QML resolves to an export', () => {
    // Arrange
    // QML resolves these at call time: a renamed export fails as an undefined
    // call in Quickshell's log, not as an error anyone sees on the bar. Nothing
    // else in this suite reaches the QML side of the boundary.
    const shell = fileURLToPath(new URL('../../linux/configs/quickshell', import.meta.url));
    const exported = new Set(Object.keys(BarLogic));
    const consumers = fs.readdirSync(shell).filter(name => name.endsWith('.qml'));

    // Act
    const called = consumers.flatMap(name => {
        const source = fs.readFileSync(path.join(shell, name), 'utf8');
        return [...source.matchAll(/BarLogic\.(\w+)/g)].map(match => ({ file: name, symbol: match[1] }));
    });

    // Assert
    assert.ok(called.length > 0, 'the QML still calls into bar-logic.mjs');
    for (const { file, symbol } of called) {
        assert.ok(exported.has(symbol), `${file} calls BarLogic.${symbol}, which bar-logic.mjs does not export`);
    }
});

// Real /proc/stat and /proc/meminfo layouts from this Fedora machine, trimmed.
const STAT = 'cpu  13820 2 7717 287861 37835 1791 476 0 0 0\ncpu0 1700 0 960 36000 4700 220 60 0 0 0\nintr 123 0\n';
const MEMINFO = 'MemTotal:       15924724 kB\nMemFree:         9667244 kB\nMemAvailable:   12203464 kB\nBuffers:            4096 kB\n';

test('cpu times read the aggregate line and count iowait as idle', () => {
    // Arrange
    const stat = STAT;

    // Act
    const times = cpuTimes(stat);

    // Assert
    // total = user..steal; busy = total - idle - iowait.
    assert.deepEqual(times, { busy: 13820 + 2 + 7717 + 1791 + 476, total: 349502 });
});

test('cpu times ignore guest columns, which are already inside user and nice', () => {
    // Arrange
    const withGuest = 'cpu  100 0 100 700 100 0 0 0 50 50\n';

    // Act
    const times = cpuTimes(withGuest);

    // Assert
    assert.deepEqual(times, { busy: 200, total: 1000 });
});

for (const { name, stat } of [
    { name: 'empty input', stat: '' },
    { name: 'missing input', stat: undefined },
    { name: 'only per-core lines', stat: 'cpu0 1 2 3 4 5 6 7 8\n' },
    { name: 'a truncated aggregate line', stat: 'cpu  1 2 3\n' },
]) {
    test(`cpu times reject ${name}`, () => {
        // Act
        const times = cpuTimes(stat);

        // Assert
        assert.equal(times, null);
    });
}

test('cpu percent is the busy share of the interval between two readings', () => {
    // Arrange
    const previous = { busy: 1000, total: 10000 };
    const current = { busy: 1250, total: 11000 };

    // Act
    const percent = cpuPercent(previous, current);

    // Assert
    assert.equal(percent, 25);
});

for (const { name, previous, current } of [
    { name: 'there is no earlier reading', previous: null, current: { busy: 1, total: 2 } },
    { name: 'the counters did not move', previous: { busy: 5, total: 10 }, current: { busy: 5, total: 10 } },
    { name: 'the counters went backwards', previous: { busy: 5, total: 10 }, current: { busy: 1, total: 4 } },
]) {
    test(`cpu percent is unknown when ${name}`, () => {
        // Act
        const percent = cpuPercent(previous, current);

        // Assert
        assert.ok(Number.isNaN(percent));
    });
}

test('cpu percent clamps a busy delta that outruns the total', () => {
    // Arrange
    const previous = { busy: 0, total: 0 };
    const current = { busy: 120, total: 100 };

    // Act
    const percent = cpuPercent(previous, current);

    // Assert
    assert.equal(percent, 100);
});

test('without a GPUReclaim line, memory usage is total minus MemAvailable, as free reports it', () => {
    // Arrange
    const meminfo = MEMINFO;

    // Act
    const usage = memoryUsage(meminfo);

    // Assert
    assert.equal(usage.percent, 23);
    assert.equal(usage.usedGiB.toFixed(1), '3.5');
    assert.equal(usage.availableGiB.toFixed(1), '11.6');
    assert.equal(usage.totalGiB.toFixed(1), '15.2');
});

test('the GPU driver buffer pool counts as available, not used', () => {
    // Arrange
    // Figures from this machine: free said 4.3 GB used, ~1.8 GB of it the
    // xe driver's reclaimable pool.
    const meminfo = 'MemTotal:       15924724 kB\nMemAvailable:   11517000 kB\n'
        + 'GPUActive:        544360 kB\nGPUReclaim:      1891132 kB\n';

    // Act
    const usage = memoryUsage(meminfo);

    // Assert
    assert.equal(usage.usedGiB.toFixed(1), '2.4');
    assert.equal(usage.availableGiB.toFixed(1), '12.8');
    assert.equal(usage.percent, 16);
});

test('available memory never exceeds the total', () => {
    // Arrange
    const meminfo = 'MemTotal: 1000 kB\nMemAvailable: 900 kB\nGPUReclaim: 500 kB\n';

    // Act
    const usage = memoryUsage(meminfo);

    // Assert
    assert.equal(usage.availableGiB, 1000 / 1048576);
    assert.equal(usage.usedGiB, 0);
    assert.equal(usage.percent, 0);
});

for (const { name, meminfo } of [
    { name: 'empty input', meminfo: '' },
    { name: 'no MemAvailable', meminfo: 'MemTotal: 100 kB\nMemFree: 50 kB\n' },
    { name: 'a zero total', meminfo: 'MemTotal: 0 kB\nMemAvailable: 0 kB\n' },
]) {
    test(`memory usage rejects ${name}`, () => {
        // Act
        const usage = memoryUsage(meminfo);

        // Assert
        assert.equal(usage, null);
    });
}

for (const { name, value, expected } of [
    { name: 'a 0-1 fraction', value: 0.85, expected: 85 },
    { name: 'a full fraction', value: 1, expected: 100 },
    { name: 'an empty fraction', value: 0, expected: 0 },
    { name: 'a 0-100 percentage', value: 64, expected: 64 },
    { name: 'an out-of-range percentage', value: 140, expected: 100 },
]) {
    test(`bluetooth battery accepts ${name}`, () => {
        // Act
        const percent = batteryPercent(value);

        // Assert
        assert.equal(percent, expected);
    });
}

for (const value of [-1, NaN, undefined, 'full']) {
    test(`bluetooth battery rejects ${String(value)}`, () => {
        // Act
        const percent = batteryPercent(value);

        // Assert
        assert.ok(Number.isNaN(percent));
    });
}

for (const { icon, expected } of [
    { icon: 'input-keyboard', expected: '\u{f030c}' },
    { icon: 'input-mouse', expected: '\u{f037d}' },
    { icon: 'input-tablet', expected: '\u{f037d}' },
    { icon: 'input-gaming', expected: '\u{f0297}' },
    { icon: 'audio-headset', expected: '\u{f02cb}' },
    { icon: 'audio-headphones', expected: '\u{f02cb}' },
    { icon: 'audio-card', expected: '\u{f04c3}' },
    { icon: 'phone', expected: '\u{f011c}' },
    { icon: 'computer', expected: '\u{f0322}' },
    { icon: '', expected: '\u{f00af}' },
    { icon: undefined, expected: '\u{f00af}' },
]) {
    test(`bluetooth device icon: ${icon || 'none'}`, () => {
        // Act
        const glyph = bluetoothDeviceIcon(icon);

        // Assert
        assert.equal(glyph, expected);
    });
}

test('bluetooth devices list the connected ones first, then by name', () => {
    // Arrange
    const devices = [
        { name: 'Slim X1 Keyboard', connected: false },
        { name: 'MX Anywhere 3S', connected: true },
        { name: 'AirPods', connected: false },
    ];

    // Act
    const ordered = [...devices].sort(compareBluetoothDevices).map(device => device.name);

    // Assert
    assert.deepEqual(ordered, ['MX Anywhere 3S', 'AirPods', 'Slim X1 Keyboard']);
});

for (const { name, id, title, expected } of [
    { name: 'nm-applet by id', id: 'nm-applet', title: '', expected: 'network' },
    { name: 'nm-applet by title', id: 'org.kde.StatusNotifierItem-1', title: 'NetworkManager Applet', expected: 'network' },
    { name: 'blueman-tray', id: 'blueman', title: 'blueman-tray', expected: 'bluetooth' },
    { name: '1Password', id: '1password', title: '1Password', expected: 'other' },
    { name: 'an item with neither field', id: undefined, title: undefined, expected: 'other' },
]) {
    test(`tray role: ${name}`, () => {
        // Act
        const role = trayRole(id, title);

        // Assert
        assert.equal(role, expected);
    });
}

for (const { name, brightness, max, expected } of [
    { name: 'this panel at 45%, as brightnessctl reports it', brightness: '86401\n', max: '192000\n', expected: 45 },
    { name: 'full', brightness: '192000', max: '192000', expected: 100 },
    { name: 'off', brightness: '0', max: '192000', expected: 0 },
    { name: 'a value past max, clamped', brightness: '200000', max: '192000', expected: 100 },
]) {
    test(`backlight percent: ${name}`, () => {
        // Act
        const percent = backlightPercent(brightness, max);

        // Assert
        assert.equal(percent, expected);
    });
}

for (const { name, brightness, max } of [
    { name: 'an unread brightness', brightness: '', max: '192000' },
    { name: 'a zero max', brightness: '10', max: '0' },
    { name: 'an unread max', brightness: '10', max: undefined },
    { name: 'a negative brightness', brightness: '-5', max: '100' },
]) {
    test(`backlight percent is unknown for ${name}`, () => {
        // Act
        const percent = backlightPercent(brightness, max);

        // Assert
        assert.ok(Number.isNaN(percent));
    });
}

for (const { name, output, internal } of [
    { name: 'the laptop panel', output: 'eDP-1', internal: true },
    { name: 'an older LVDS panel', output: 'LVDS-1', internal: true },
    { name: 'no focused monitor yet', output: '', internal: true },
    { name: 'the Dell over USB-C', output: 'DP-1', internal: false },
    { name: 'an HDMI monitor', output: 'HDMI-A-1', internal: false },
]) {
    test(`brightness source for ${name} is ${internal ? 'the backlight' : 'DDC'}`, () => {
        // Act
        const isPanel = isInternalOutput(output);

        // Assert
        assert.equal(isPanel, internal);
    });
}

test('an external level published for the focused monitor is read as a percent', () => {
    // Arrange: what brightness.sh writes to $XDG_RUNTIME_DIR/initd-brightness/level
    const published = 'DP-1 66\n';

    // Act
    const percent = externalBrightness(published, 'DP-1');

    // Assert
    assert.equal(percent, 66);
});

for (const { name, text, output } of [
    { name: 'a level left by the other monitor', text: 'DP-1 66\n', output: 'DP-2' },
    { name: 'no file yet', text: '', output: 'DP-1' },
    { name: 'a half-written line', text: 'DP-1\n', output: 'DP-1' },
    { name: 'a value past 100', text: 'DP-1 140\n', output: 'DP-1' },
    { name: 'a non-number', text: 'DP-1 lots\n', output: 'DP-1' },
]) {
    test(`external level is unknown for ${name}`, () => {
        // Act
        const percent = externalBrightness(text, output);

        // Assert
        assert.ok(Number.isNaN(percent));
    });
}

// Real `df -P -B1 /` from this machine: a LUKS-wrapped btrfs volume.
const DF = 'Filesystem 1-blocks Used Available Capacity Mounted on\n'
    + '/dev/mapper/luks-b2d6 509315383296 23384498176 485564669952 5% /\n';

test('disk usage reads free space and df-style capacity', () => {
    // Act
    const usage = diskUsage(DF);

    // Assert
    assert.equal(usage.availableGiB.toFixed(1), '452.2');
    assert.equal(usage.totalGiB.toFixed(1), '474.3');
    assert.equal(usage.percent, 5);
});

test('disk capacity divides by used + available, not size, like df on btrfs', () => {
    // Arrange
    // size 1000 but used + available only 800: df reports 50%, not 40%.
    const dfOutput = 'Filesystem 1-blocks Used Available Capacity Mounted on\nx 1000 400 400 50% /\n';

    // Act
    const usage = diskUsage(dfOutput);

    // Assert
    assert.equal(usage.percent, 50);
});

for (const { name, dfOutput } of [
    { name: 'empty output', dfOutput: '' },
    { name: 'a header only', dfOutput: 'Filesystem 1-blocks Used Available Capacity Mounted on\n' },
    { name: 'a truncated row', dfOutput: 'Filesystem\nx 1000 400\n' },
    { name: 'a zero size', dfOutput: 'Filesystem\nx 0 0 0 0% /\n' },
]) {
    test(`disk usage rejects ${name}`, () => {
        // Act
        const usage = diskUsage(dfOutput);

        // Assert
        assert.equal(usage, null);
    });
}

for (const { gib, expected } of [
    { gib: 452.2, expected: '452G' },
    { gib: 9.46, expected: '9.5G' },
    { gib: 0.4, expected: '0.4G' },
    { gib: 2048, expected: '2.0T' },
    { gib: NaN, expected: '--' },
]) {
    test(`free space formats ${gib} GiB as ${expected}`, () => {
        // Act
        const text = formatGiB(gib);

        // Assert
        assert.equal(text, expected);
    });
}

test('greeting splits the day at 5, 12 and 18', () => {
    // Arrange / Act / Assert
    assert.equal(BarLogic.greeting(0), 'Good night');
    assert.equal(BarLogic.greeting(4), 'Good night');
    assert.equal(BarLogic.greeting(5), 'Good morning');
    assert.equal(BarLogic.greeting(11), 'Good morning');
    assert.equal(BarLogic.greeting(12), 'Good afternoon');
    assert.equal(BarLogic.greeting(17), 'Good afternoon');
    assert.equal(BarLogic.greeting(18), 'Good evening');
    assert.equal(BarLogic.greeting(23), 'Good evening');
});

test('fraction turns a bar readout into a clamped 0..1 value', () => {
    assert.equal(BarLogic.fraction('42%'), 0.42);
    assert.equal(BarLogic.fraction('100%'), 1);
    assert.equal(BarLogic.fraction('130%'), 1);
    assert.equal(BarLogic.fraction('--%'), 0);
    assert.equal(BarLogic.fraction(''), 0);
});

test('trackTime formats Mpris seconds as m:ss or h:mm:ss', () => {
    assert.equal(BarLogic.trackTime(0), '0:00');
    assert.equal(BarLogic.trackTime(65.9), '1:05');
    assert.equal(BarLogic.trackTime(3725), '1:02:05');
    assert.equal(BarLogic.trackTime(-3), '0:00');
    assert.equal(BarLogic.trackTime(NaN), '0:00');
});

test('bar-logic.mjs avoids syntax the QML JavaScript engine rejects', () => {
    // Node accepts these, so every other test here passes, but Quickshell's
    // V4 engine refuses the module and the whole bar fails to load. An
    // optional catch binding (`catch {`) took the bar down once already.
    // Arrange
    const source = fs.readFileSync(fileURLToPath(new URL(
        '../../linux/configs/quickshell/bar-logic.mjs', import.meta.url)), 'utf8');
    // Act / Assert
    assert.doesNotMatch(source, /\bcatch\s*\{/, 'use `catch (error) {`');
});

test('themeColors takes valid roles from theme.json and defaults the rest', () => {
    // Arrange
    const text = JSON.stringify({ wallpaper: '/w.jpg', colors: {
        accent: '#FFB4A8', text: '#ffffff', bar: '#b3201a19',
        textMuted: 'red', menu: '#12345', bogus: '#000000',
    } });
    // Act
    const colors = BarLogic.themeColors(text);
    // Assert
    assert.equal(colors.accent, '#ffb4a8');
    assert.equal(colors.text, '#ffffff');
    assert.equal(colors.bar, '#b3201a19');
    assert.equal(colors.textMuted, BarLogic.THEME_DEFAULTS.textMuted);
    assert.equal(colors.menu, BarLogic.THEME_DEFAULTS.menu);
    assert.equal(colors.bogus, undefined);
});

test('themeColors falls back to the whole default palette on a bad file', () => {
    for (const text of ['', '{', 'null', '[]', '{"colors": 3}'])
        assert.deepEqual(BarLogic.themeColors(text), BarLogic.THEME_DEFAULTS, text);
});

test('the switcher lists mapped windows most recently used first, with the active one pinned', () => {
    // Arrange: history says kitty (0) then Brave (1) then Files (2), but the
    // active window is Brave -- its history ID has not caught up yet.
    const kitty = { lastIpcObject: { address: '0x1', focusHistoryID: 0, mapped: true, hidden: false } };
    const brave = { lastIpcObject: { address: '0x2', focusHistoryID: 1, mapped: true, hidden: false } };
    const files = { lastIpcObject: { address: '0x3', focusHistoryID: 2, mapped: true, hidden: false } };
    const unmapped = { lastIpcObject: { address: '0x4', focusHistoryID: 3, mapped: false, hidden: false } };
    const hidden = { lastIpcObject: { address: '0x5', focusHistoryID: 4, mapped: true, hidden: true } };
    const noIpc = { lastIpcObject: null };

    // Act
    const order = switcherOrder([files, hidden, noIpc, kitty, unmapped, brave], brave);

    // Assert
    assert.deepEqual(order, [brave, kitty, files]);
});

test('the switcher selection wraps in both directions', () => {
    assert.equal(switcherStep(1, 1, 3), 2);
    assert.equal(switcherStep(2, 1, 3), 0);
    assert.equal(switcherStep(0, -1, 3), 2);
    assert.equal(switcherStep(5, 1, 0), 0);
});

test('bannerTimeout defaults to 3 s, clamps requests to 2-8 s, and pins critical', () => {
    assert.equal(BarLogic.bannerTimeout(-1, false), 3000);
    assert.equal(BarLogic.bannerTimeout(0, false), 3000);
    assert.equal(BarLogic.bannerTimeout(undefined, false), 3000);
    assert.equal(BarLogic.bannerTimeout(1, false), 2000);
    assert.equal(BarLogic.bannerTimeout(5, false), 5000);
    assert.equal(BarLogic.bannerTimeout(600, false), 8000);
    assert.equal(BarLogic.bannerTimeout(8, true), 0);
});

test('wifiNetworkList dedupes by name and orders connected, saved, then signal', () => {
    // Arrange: "Home" broadcast by two access points; one hidden network.
    const networks = [
        { name: 'Cafe', known: false, connected: false, signalStrength: 0.9 },
        { name: 'Home', known: true, connected: false, signalStrength: 0.4 },
        { name: 'Home', known: true, connected: true, signalStrength: 0.3 },
        { name: 'Office', known: true, connected: false, signalStrength: 0.7 },
        { name: '', known: false, connected: false, signalStrength: 1 },
        { name: 'Weak', known: false, connected: false, signalStrength: 0.1 },
    ];
    // Act
    const list = BarLogic.wifiNetworkList(networks);
    // Assert
    assert.deepEqual(list.map((n) => n.name), ['Home', 'Office', 'Cafe', 'Weak']);
    assert.equal(list[0].connected, true);
    assert.deepEqual(BarLogic.wifiNetworkList(null), []);
});

test('wifiSignalIcon picks one of four bars and accepts 0-100 readings', () => {
    assert.equal(BarLogic.wifiSignalIcon(0.9), '\u{f0928}');
    assert.equal(BarLogic.wifiSignalIcon(90), '\u{f0928}');
    assert.equal(BarLogic.wifiSignalIcon(0.6), '\u{f0925}');
    assert.equal(BarLogic.wifiSignalIcon(0.3), '\u{f0922}');
    assert.equal(BarLogic.wifiSignalIcon(0.05), '\u{f091f}');
    assert.equal(BarLogic.wifiSignalIcon(undefined), '\u{f091f}');
});
