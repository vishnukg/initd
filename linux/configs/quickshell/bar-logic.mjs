// Pure presentation logic for the bar, kept out of the QML so it can be tested
// with `node --test` like every other .mjs in this repo. Imported by shell.qml
// and AudioMenu.qml as an ES module; QML keeps the thin wrappers that read its
// own properties, so nothing here touches Quickshell state.
//
// Everything below is ordering-sensitive on purpose - see the comments.

export function clockMinutes(value) {
    const match = /(\d{1,2}):(\d{2})/.exec(value);
    if (!match)
        return -1;
    let hours = parseInt(match[1], 10);
    const minutes = parseInt(match[2], 10);
    if (/PM/i.test(value) && hours < 12)
        hours += 12;
    if (/AM/i.test(value) && hours === 12)
        hours = 0;
    return hours * 60 + minutes;
}

// `minutes` is the caller's clock reading, so the caller owns "now" and this
// stays a function of its arguments.
export function isNight(sunriseText, sunsetText, minutes) {
    const sunrise = clockMinutes(sunriseText);
    const sunset = clockMinutes(sunsetText);
    if (sunrise < 0 || sunset < 0)
        return false;
    return minutes < sunrise || minutes >= sunset;
}

// WWO condition names are a fixed vocabulary ("Patchy light rain with
// thunder", "Moderate or heavy sleet showers", ...), so keyword tests in
// severity order cover the whole set without a 48-entry lookup table.
// The order is the specification: "Freezing fog" must reach the fog test
// before the freezing one, or it draws as sleet.
export function weatherIcon(condition, night) {
    const text = (condition || "").toLowerCase();
    if (text.indexOf("thunder") >= 0)
        return text.indexOf("rain") >= 0 || text.indexOf("snow") >= 0
            ? "\u{f067e}"
            : "\u{f0593}";
    if (text.indexOf("ice pellets") >= 0 || text.indexOf("hail") >= 0)
        return "\u{f0592}";
    if (text.indexOf("fog") >= 0)
        return "\u{f0591}";
    if (text.indexOf("mist") >= 0 || text.indexOf("haze") >= 0)
        return "\u{f0f30}";
    if (text.indexOf("sleet") >= 0 || text.indexOf("freezing") >= 0)
        return "\u{f067f}";
    if (text.indexOf("blizzard") >= 0 || text.indexOf("heavy snow") >= 0)
        return "\u{f0f36}";
    if (text.indexOf("snow") >= 0)
        return text.indexOf("patchy") >= 0 ? "\u{f0f35}" : "\u{f0598}";
    if (text.indexOf("torrential") >= 0 || text.indexOf("heavy rain") >= 0)
        return "\u{f0596}";
    if (text.indexOf("rain") >= 0 || text.indexOf("drizzle") >= 0
            || text.indexOf("shower") >= 0)
        return text.indexOf("patchy") >= 0 ? "\u{f0f33}" : "\u{f0597}";
    if (text.indexOf("partly") >= 0)
        return night ? "\u{f0f31}" : "\u{f0595}";
    if (text.indexOf("cloud") >= 0 || text.indexOf("overcast") >= 0)
        return "\u{f0590}";
    if (text.indexOf("sunny") >= 0)
        return "\u{f0599}";
    if (text.indexOf("clear") >= 0)
        return night ? "\u{f0594}" : "\u{f0599}";
    return "\u{f0f2f}";
}

export function weatherCelsius(temperature) {
    const match = /(-?\d+(?:\.\d+)?)/.exec(temperature);
    if (!match)
        return NaN;
    const value = parseFloat(match[1]);
    return /F/i.test(temperature) ? (value - 32) * 5 / 9 : value;
}

// Mild weather says nothing, so it stays flat: colour only appears once the
// reading is cold enough or hot enough to be worth noticing, deepening as
// it gets further from comfortable.
export function weatherColor(celsius) {
    if (isNaN(celsius))
        return "#e8eaf0";
    if (celsius <= 0)
        return "#6fa8e0";
    if (celsius < 6)
        return "#8fb7e8";
    if (celsius < 12)
        return "#8fd8e8";
    if (celsius <= 25)
        return "#e8eaf0";
    if (celsius < 30)
        return "#e8b87a";
    if (celsius < 35)
        return "#e89a8f";
    return "#e0788a";
}

export function loadColor(reading) {
    const percent = parseInt(reading, 10);
    if (isNaN(percent))
        return "#e8eaf0";
    if (percent >= 90)
        return "#e0788a";
    if (percent >= 70)
        return "#e8b87a";
    return "#e8eaf0";
}

// HDMI and USB endpoints are ALSA devices too, so they must be matched before
// the generic alsa_ test claims them as Built-in.
export function deviceKind(name) {
    const text = (name || "").toLowerCase();
    if (text.indexOf("bluez") !== -1)
        return "Bluetooth";
    if (text.indexOf("raop") !== -1)
        return "AirPlay";
    if (text.indexOf("hdmi") !== -1 || text.indexOf("displayport") !== -1)
        return "HDMI";
    if (text.indexOf("usb") !== -1)
        return "USB";
    if (text.indexOf("alsa_") !== -1)
        return "Built-in";
    return "Virtual";
}

// Rows are grouped so the laptop's own speaker and mic keep a stable position
// regardless of what is plugged in.
export const KIND_ORDER = ["Built-in", "USB", "HDMI", "Bluetooth", "AirPlay", "Virtual"];

export function kindRank(name) {
    const index = KIND_ORDER.indexOf(deviceKind(name));
    return index === -1 ? KIND_ORDER.length : index;
}

// /proc/stat's aggregate line is jiffies since boot:
//   cpu  user nice system idle iowait irq softirq steal guest guest_nice
// Only the first eight are summed: guest time is already counted inside user
// and nice, so adding the last two would double count a running VM. Idle is
// idle *plus* iowait - waiting on the disk is not CPU load, and counting it
// pinned the old readout near 40% on an idle machine.
export function cpuTimes(stat) {
    const match = /^cpu\s+(.+)$/m.exec(stat || "");
    if (!match)
        return null;
    const fields = match[1].trim().split(/\s+/).slice(0, 8).map(Number);
    if (fields.length < 5 || fields.some(isNaN))
        return null;
    const total = fields.reduce(function (sum, value) { return sum + value; }, 0);
    return { busy: total - fields[3] - fields[4], total: total };
}

// Busy share of the interval between two cpuTimes() readings. NaN until there
// are two readings to compare, and for a counter that did not move or went
// backwards (a suspend/resume can do either), so the bar keeps "--%" rather
// than inventing a number.
export function cpuPercent(previous, current) {
    if (!previous || !current)
        return NaN;
    const total = current.total - previous.total;
    if (total <= 0)
        return NaN;
    const busy = (current.busy - previous.busy) * 100 / total;
    return Math.round(Math.min(100, Math.max(0, busy)));
}

// Available is MemAvailable plus GPUReclaim; used is the rest of MemTotal.
// MemAvailable already counts page cache and reclaimable slab as available,
// but not the GPU driver's buffer pool (GPUReclaim, xe/TTM), which the
// kernel shrinks under pressure just the same. On this Intel iGPU that pool
// sits around 1.9 GB, so without it the bar (and `free`) read ~4.3 GB used
// for ~2.4 GB of real use. Kernels without the GPUReclaim line fall back to
// plain MemAvailable. /proc/meminfo is in kB (KiB).
export function memoryUsage(meminfo) {
    function read(key) {
        const match = new RegExp("^" + key + ":\\s+(\\d+)", "m").exec(meminfo || "");
        return match ? Number(match[1]) : NaN;
    }
    const total = read("MemTotal");
    const memAvailable = read("MemAvailable");
    if (!(total > 0) || isNaN(memAvailable))
        return null;
    const gpuReclaim = read("GPUReclaim");
    const available = Math.min(total, memAvailable + (isNaN(gpuReclaim) ? 0 : gpuReclaim));
    const used = Math.max(0, total - available);
    return {
        percent: Math.round(used * 100 / total),
        usedGiB: used / 1048576,
        availableGiB: available / 1048576,
        totalGiB: total / 1048576,
    };
}

// BlueZ reports Battery1.Percentage as 0-100 and Quickshell normalises it to
// 0-1; accepting both keeps a future change on either side from rendering
// "1%" for a full mouse.
export function batteryPercent(value) {
    const number = Number(value);
    if (!isFinite(number) || number < 0)
        return NaN;
    return Math.round(number <= 1 ? number * 100 : Math.min(number, 100));
}

// BlueZ's device Icon is a freedesktop icon name ("input-mouse",
// "audio-headset"); the bar wants a Nerd Font glyph like every other item.
// Prefix matches, because BlueZ appends nothing consistent after the class.
export function bluetoothDeviceIcon(icon) {
    const name = (icon || "").toLowerCase();
    if (name.indexOf("input-keyboard") === 0)
        return "\u{f030c}";
    if (name.indexOf("input-mouse") === 0 || name.indexOf("input-tablet") === 0)
        return "\u{f037d}";
    if (name.indexOf("input-gaming") === 0)
        return "\u{f0297}";
    if (name.indexOf("audio-headset") === 0 || name.indexOf("audio-headphones") === 0)
        return "\u{f02cb}";
    if (name.indexOf("audio") === 0)
        return "\u{f04c3}";
    if (name.indexOf("phone") === 0)
        return "\u{f011c}";
    if (name.indexOf("computer") === 0)
        return "\u{f0322}";
    return "\u{f00af}";
}

// Connected devices first, then by name, so the one in use is always the top
// row and the rest do not reshuffle as signal comes and goes.
export function compareBluetoothDevices(a, b) {
    if (!!a.connected !== !!b.connected)
        return a.connected ? -1 : 1;
    return (a.name || "").localeCompare(b.name || "");
}

// Which slot a StatusNotifierItem takes in the bar. nm-applet gets the custom
// Wi-Fi icon and menu; blueman's is dropped, because the bar draws Bluetooth
// natively and blueman-applet runs headless as BlueZ's pairing agent - the
// filter covers a session still running blueman-tray from before that change,
// which would otherwise show a second Bluetooth icon until the next login.
export function trayRole(id, title) {
    const identity = ((id || "") + " " + (title || "")).toLowerCase();
    if (identity.indexOf("networkmanager") !== -1 || identity.indexOf("nm-applet") !== -1)
        return "network";
    if (identity.indexOf("blueman") !== -1)
        return "bluetooth";
    return "other";
}

// Backlight level as brightnessctl reports it: the raw sysfs value over
// max_brightness, as a rounded percentage. NaN for anything unreadable, so
// the bar keeps its last reading rather than drawing a bogus one.
export function backlightPercent(brightness, maxBrightness) {
    const value = parseInt(brightness, 10);
    const max = parseInt(maxBrightness, 10);
    if (isNaN(value) || !(max > 0) || value < 0)
        return NaN;
    return Math.round(Math.min(value, max) * 100 / max);
}

// Whether an output name is the laptop's own panel (the kernel's DRM
// connector names for internal panels), which brightness.sh steers through
// the backlight; anything else is an external monitor reached over DDC/CI.
// No name at all (no focused monitor yet) counts as the panel.
export function isInternalOutput(name) {
    return !name || /^(eDP|LVDS|DSI)/.test(name);
}

// The level brightness.sh publishes for an external monitor: a line
// "<output> <percent>". NaN unless it is for the output asked about, so a
// stale line left by the other monitor is never shown as this one's level.
export function externalBrightness(levelText, output) {
    const fields = (levelText || "").trim().split(/\s+/);
    if (fields.length !== 2 || fields[0] !== output)
        return NaN;
    const percent = parseInt(fields[1], 10);
    if (isNaN(percent) || percent < 0 || percent > 100 || String(percent) !== fields[1])
        return NaN;
    return percent;
}

// `df -P -B1 /`: a header, then "fs size used available capacity mountpoint"
// in bytes. The percentage is used / (used + available), which is how df
// computes Capacity -- on btrfs size != used + available (metadata, reserved
// space), so dividing by size would under-read. Null for anything unparsable.
export function diskUsage(dfOutput) {
    const lines = (dfOutput || "").trim().split("\n");
    if (lines.length < 2)
        return null;
    const fields = lines[lines.length - 1].trim().split(/\s+/);
    if (fields.length < 6)
        return null;
    const size = Number(fields[1]), used = Number(fields[2]), available = Number(fields[3]);
    if (!(size > 0) || isNaN(used) || isNaN(available) || used + available <= 0)
        return null;
    return {
        percent: Math.round(used * 100 / (used + available)),
        availableGiB: available / 1073741824,
        totalGiB: size / 1073741824,
    };
}

// Free space for the bar: one decimal under 10 GiB, where it matters,
// whole GiB above, and TiB once a disk has that much.
export function formatGiB(gib) {
    if (!isFinite(gib) || gib < 0)
        return "--";
    if (gib >= 1024)
        return (gib / 1024).toFixed(1) + "T";
    if (gib < 10)
        return gib.toFixed(1) + "G";
    return Math.round(gib) + "G";
}

// Interfaces whose traffic is either local or already counted on a physical
// link: loopback, container/VM bridges and veths, and VPN tunnels (a packet
// through wg0 also crosses the Wi-Fi underneath it, so summing both would
// double it).
const VIRTUAL_INTERFACE = /^(lo|docker\d*|br-|veth|virbr|vnet|tun|tap|wg|tailscale|zt)/;

// /proc/net/dev: two header lines, then "iface: rx_bytes ... tx_bytes ...",
// where rx bytes is the first number and tx bytes the ninth. Sums every
// physical interface and lists them for the tooltip. Null when nothing
// parses.
export function netBytes(procNetDev) {
    let rx = 0, tx = 0;
    const interfaces = [];
    for (const line of (procNetDev || "").split("\n")) {
        const match = /^\s*([^:\s]+):\s*(.*)$/.exec(line);
        if (!match || VIRTUAL_INTERFACE.test(match[1]))
            continue;
        const fields = match[2].trim().split(/\s+/).map(Number);
        if (fields.length < 9 || isNaN(fields[0]) || isNaN(fields[8]))
            continue;
        rx += fields[0];
        tx += fields[8];
        interfaces.push(match[1]);
    }
    return interfaces.length ? { rx: rx, tx: tx, interfaces: interfaces } : null;
}

// Bytes per second between two netBytes() readings taken `seconds` apart.
// Null until there are two readings; a counter that went backwards (an
// interface vanished, or a driver reset) reads as 0 rather than negative.
export function netRate(previous, current, seconds) {
    if (!previous || !current || !(seconds > 0))
        return null;
    return {
        down: Math.max(0, current.rx - previous.rx) / seconds,
        up: Math.max(0, current.tx - previous.tx) / seconds,
    };
}

// At most four characters, so the item's width barely moves: "0K", "9.5K",
// "340K", "1.2M", "45M", "1.1G". KiB-based, like the other readouts.
export function formatRate(bytesPerSecond) {
    if (!isFinite(bytesPerSecond) || bytesPerSecond < 0)
        return "--";
    const units = ["K", "M", "G"];
    let value = bytesPerSecond / 1024;
    let unit = 0;
    while (value >= 999.5 && unit < units.length - 1) {
        value /= 1024;
        unit += 1;
    }
    if (value < 0.05)
        return "0" + units[unit];
    return (value < 9.95 ? value.toFixed(1) : String(Math.round(value))) + units[unit];
}

// --- Desktop widgets (DesktopWidgets.qml) ---

// The greeting over the desktop clock. Night owls get "Good night" until 5,
// then the day splits at noon and 18:00.
export function greeting(hour) {
    if (hour < 5) return 'Good night';
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
}

// "42%" -> 0.42, clamped to [0, 1]; the bar's readouts are strings, the
// rings want a fraction. Anything unparsable ("--%") reads as 0.
export function fraction(percentText) {
    const value = parseFloat(percentText);
    if (!isFinite(value)) return 0;
    return Math.min(1, Math.max(0, value / 100));
}

// Mpris position/length (seconds) -> "m:ss", or "h:mm:ss" past an hour.
// Unknown or negative reads as "0:00".
export function trackTime(seconds) {
    const total = isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0;
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const secs = String(total % 60).padStart(2, '0');
    return hours > 0
        ? hours + ':' + String(minutes).padStart(2, '0') + ':' + secs
        : minutes + ':' + secs;
}

// --- Theme (Theme.qml) ---

// The roles Theme.qml exposes, with the hand-tuned dark palette the bar had
// before wallpaper theming. A role missing from theme.json, or holding
// anything but a #rrggbb / #aarrggbb colour, keeps its default -- so a
// half-written or corrupt file degrades to the old look, never to black.
export const THEME_DEFAULTS = {
    accent: '#8fb7e8',
    onAccent: '#0b0c10',
    text: '#e8eaf0',
    textMuted: '#aeb4c3',
    textDim: '#656a78',
    textDisabled: '#52566a',
    bar: '#b30b0c10',
    menu: '#f20d0e12',
    good: '#8fd6b8',
    warn: '#e8b87a',
    bad: '#e0788a',
};

export function themeColors(text) {
    const result = Object.assign({}, THEME_DEFAULTS);
    let parsed;
    try {
        parsed = JSON.parse(text);
    } catch (error) {
        return result;
    }
    const colors = parsed && typeof parsed === 'object' ? parsed.colors : null;
    if (!colors || typeof colors !== 'object')
        return result;
    for (const role of Object.keys(THEME_DEFAULTS)) {
        const value = colors[role];
        if (typeof value === 'string' && /^#([0-9a-f]{6}|[0-9a-f]{8})$/i.test(value))
            result[role] = value.toLowerCase();
    }
    return result;
}

// --- Notifications (Notifications.qml) ---

// How long a banner stays up, in ms. `expireTimeout` is the app's request in
// seconds as Quickshell reports it (<= 0: "server default"). Critical ones
// stay until dismissed (0 = no timer); everything else gets the request
// clamped to 3-15 s, or 5 s by default, so no app can pin a banner.
export function bannerTimeout(expireTimeout, critical) {
    if (critical)
        return 0;
    const seconds = Number(expireTimeout);
    if (!(seconds > 0))
        return 5000;
    return Math.round(Math.min(15, Math.max(3, seconds)) * 1000);
}

// --- Wi-Fi page (QuickSettings.qml) ---

// Signal strength as a 0..1 fraction; Quickshell reports 0..1, but a 0..100
// reading is accepted too so a backend change cannot zero every bar.
export function signalFraction(strength) {
    const value = Number(strength);
    if (!isFinite(value) || value <= 0)
        return 0;
    return Math.min(1, value > 1 ? value / 100 : value);
}

// nf-md-wifi_strength_1..4 by signal.
export function wifiSignalIcon(strength) {
    const s = signalFraction(strength);
    if (s >= 0.75) return "\u{f0928}";
    if (s >= 0.5) return "\u{f0925}";
    if (s >= 0.25) return "\u{f0922}";
    return "\u{f091f}";
}

// The networks to list: one row per name (several access points broadcast the
// same network; the strongest stands for it), hidden/unnamed ones dropped,
// connected first, then saved, then by signal.
export function wifiNetworkList(networks) {
    const best = {};
    for (let i = 0; i < (networks || []).length; i++) {
        const n = networks[i];
        if (!n || !n.name)
            continue;
        const current = best[n.name];
        const rank = (x) => (x.connected ? 2 : 0) + signalFraction(x.signalStrength);
        if (!current || rank(n) > rank(current))
            best[n.name] = n;
    }
    return Object.keys(best).map((name) => best[name]).sort((a, b) => {
        if (!!a.connected !== !!b.connected) return a.connected ? -1 : 1;
        if (!!a.known !== !!b.known) return a.known ? -1 : 1;
        return signalFraction(b.signalStrength) - signalFraction(a.signalStrength);
    });
}
