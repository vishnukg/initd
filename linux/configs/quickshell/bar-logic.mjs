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
