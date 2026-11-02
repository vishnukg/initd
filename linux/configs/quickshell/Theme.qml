pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "bar-logic.mjs" as BarLogic

// The bar's palette, by role. Defaults are the hand-tuned dark palette the
// bar always had; linux/scripts/theme.mjs rewrites
// ~/.local/state/initd/theme.json from the wallpaper (matugen) and this
// picks the change up through an inotify watch -- no polling, no restart.
// BarLogic.themeColors() validates every role, so a missing or corrupt file
// keeps the defaults rather than painting the bar black.
//
// Status colours (good/warn/bad) are fixed by theme.mjs: in this bar colour
// means state, and "low battery" has to read as red whatever the wallpaper.
//
// No colour easing on purpose: a Behavior on these properties segfaults
// Quickshell 0.2.1 at load -- on the Singleton directly, and with this many
// roles even on an inner Item (each reproduced in isolation; only a single
// trivial binding survived). A wallpaper change snaps the palette instead.
Singleton {
    id: theme

    // Straight from theme.json, validated.
    property var raw: BarLogic.THEME_DEFAULTS

    readonly property color accent: raw.accent
    readonly property color onAccent: raw.onAccent
    readonly property color text: raw.text
    readonly property color textMuted: raw.textMuted
    readonly property color textDim: raw.textDim
    readonly property color textDisabled: raw.textDisabled
    readonly property color bar: raw.bar
    readonly property color menu: raw.menu
    readonly property color good: raw.good
    readonly property color warn: raw.warn
    readonly property color bad: raw.bad


    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.local/state/initd/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: theme.raw = BarLogic.themeColors(text())
        // A missing file (before the first theme run) keeps the defaults.
        onLoadFailed: theme.raw = BarLogic.THEME_DEFAULTS
    }
}
