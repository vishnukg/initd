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
