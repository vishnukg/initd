//@ pragma UseQApplication

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
// Pure presentation logic, shared with AudioMenu.qml and covered by
// tests/linux/bar-logic.test.mjs.
import "bar-logic.mjs" as BarLogic

ShellRoot {
    id: root

    property bool barVisible: true
    property string cpuText: "--%"
    property string cpuTooltip: "CPU usage unavailable"
    property string memoryText: "--G"
    property string memoryPercent: "--%"
    property string memoryTooltip: "Memory usage unavailable"
    property string diskText: "--"
    property string diskPercent: "--%"
    property string diskTooltip: "Disk usage unavailable"
    property string dockerText: "0"
    property string weatherTemp: "--"
    property string weatherCondition: "Unavailable"
    property string weatherSunrise: ""
    property string weatherSunset: ""
    // Brightness of the focused monitor: the panel's backlight from sysfs, an
    // external monitor's DDC level from the file brightness.sh publishes.
    property string backlightText: "--%"
    property real backlightValue: 0
    property bool brightnessFromKeys: false
    readonly property string focusedOutput: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    readonly property bool focusedIsPanel: BarLogic.isInternalOutput(focusedOutput)
    onFocusedOutputChanged: refreshBrightnessSource()
    readonly property var clockDate: clock.date

    // Quick settings (QuickSettings.qml), created only while open.
    property bool panelOpen: false
    // When the sheet last closed: a click on the bar button first clears the
    // sheet's focus grab (closing it), and must not then reopen it.
    property real panelClosedAt: 0
    onPanelOpenChanged: {
        if (!panelOpen)
            panelClosedAt = Date.now();
        // The slider is about to show; an external monitor's level may have
        // moved on its own OSD since it was last asked, so ask once.
        else if (!focusedIsPanel)
            start(brightnessRefreshProcess);
    }
    // Inhibits idle (no auto-lock or screen-off) through every bar window.
    property bool keepAwake: false
    // Workspace overview (Overview.qml), created only while open.
    property bool overviewOpen: false

    // Window switcher (AltTab.qml) on Alt+Tab. The list is the open windows
    // in most-recently-used order, taken once when the row opens so it does
    // not reshuffle under the selection. Every press moves the selection, and
    // the focus follows 150 ms after the last press (switcherFocus): one
    // Alt+Tab is the previous window, a second Tab while the row is up is
    // the one before that, and so on, wrapping. The
    // row closes 0.6 s after the last press (switcherHide: long enough for the next Tab of a run, short enough to be gone when you stop), and with it the
    // snapshot, so the next Alt+Tab starts from the new order. There is no
    // "release Alt to commit": Hyprland suppresses a bare Alt release bind
    // once Alt+Tab has fired (src/keybinds/Manager.cpp, suppressSubChords),
    // so a release can never be observed from a bind.
    property bool switcherOpen: false
    property int switcherIndex: 0
    property var switcherWindows: []

    function altTab(step) {
        if (!switcherOpen) {
            const windows = BarLogic.switcherOrder(Hyprland.toplevels.values, Hyprland.activeToplevel);
            if (windows.length < 2) {
                // A window opened since the last refresh has no IPC data yet
                // (Quickshell fills lastIpcObject only on refreshToplevels),
                // so it was filtered out. Refresh and retry this one press.
                Hyprland.refreshToplevels();
                switcherRetry.step = step;
                switcherRetry.restart();
                return;
            }
            switcherWindows = windows;
            switcherIndex = 0;
            switcherOpen = true;
        }
        switcherIndex = BarLogic.switcherStep(switcherIndex, step, switcherWindows.length);
        // The selection moves at once; the focus follows 150 ms after the
        // last press, so a run of Tabs lands on one window instead of
        // hopping through each one on the way.
        switcherFocus.restart();
        switcherHide.restart();
    }

    Timer {
        id: switcherFocus
        interval: 150
        onTriggered: root.focusSwitcherSelection()
    }

    Timer {
        id: switcherRetry
        property int step: 1
        interval: 120
        onTriggered: {
            if (BarLogic.switcherOrder(Hyprland.toplevels.values, Hyprland.activeToplevel).length >= 2)
                root.altTab(step);
        }
    }

    // Keep every window's IPC data (geometry, focus history) current: once
    // at startup (Quickshell lists toplevels without it until asked), then
    // as windows come and go, so the switcher's first press already knows
    // every window. Open and close are rare; one query each.
    Component.onCompleted: Hyprland.refreshToplevels()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow")
                Hyprland.refreshToplevels();
        }
    }

    function focusSwitcherSelection() {
        const chosen = switcherWindows[switcherIndex];
        const ipc = chosen ? chosen.lastIpcObject : null;
        if (ipc && ipc.address) {
            Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + ipc.address + "\" })");
            Hyprland.dispatch("hl.dsp.window.alter_zorder({ mode = \"top\" })");
        }
    }

    // A click on a card: select and focus it, and close at once.
    function altTabCommit() {
        if (!switcherOpen)
            return;
        switcherFocus.stop();
        focusSwitcherSelection();
        altTabCancel();
    }

    function altTabCancel() {
        // A cancel while a focus is pending (the backdrop clicked, or the
        // row timing out right after a press) still lands the selection.
        if (switcherFocus.running) {
            switcherFocus.stop();
            focusSwitcherSelection();
        }
        switcherHide.stop();
        switcherOpen = false;
        switcherWindows = [];
        // Geometry and focus history current for the next open.
        Hyprland.refreshToplevels();
    }

    Timer {
        id: switcherHide
        interval: 600
        onTriggered: root.altTabCancel()
    }

    function togglePanel() {
        if (!panelOpen && Date.now() - panelClosedAt < 300)
            return;
        panelOpen = !panelOpen;
    }

    // The tile flips at once; the switch itself takes up to ~4 s (gammastep
    // fades the gamma back before it exits, and systemd waits for it), and
    // the toggle script's refreshNightLight ping then confirms the real
    // state, or puts the tile back if the switch failed. A click while the
    // switch is still running is ignored rather than queued.
    function toggleNightLight() {
        if (nightLightToggleProcess.running)
            return;
        nightLightOn = !nightLightOn;
        start(nightLightToggleProcess);
    }

    // The brightness slider fires on every pixel of a drag; run brightness.sh
    // one at a time and always finish on the latest value. `set` does not
    // ping refreshBrightness (only the keys do), so the slider never raises
    // the indicator; the exit handler reloads the level instead.
    property int brightnessPending: -1
    function setBrightness(fraction) {
        brightnessPending = Math.round(Math.max(0.02, Math.min(1, fraction)) * 100);
        backlightValue = brightnessPending / 100;
        if (!brightnessProcess.running) {
            brightnessProcess.command = [Quickshell.env("HOME") + "/.config/brightness.sh", "set", String(brightnessPending)];
            brightnessPending = -1;
            brightnessProcess.running = true;
        }
    }

    // Re-read the focused monitor's level from its source: the sysfs file for
    // the panel; for an external monitor, ask brightness.sh to query it over
    // DDC and publish (one ~0.4 s process, only on a focus change or when the
    // quick settings open -- the keys and the slider publish as they write).
    function refreshBrightnessSource() {
        brightnessFromKeys = false;
        if (focusedIsPanel)
            backlightFile.reload();
        else
            start(brightnessRefreshProcess);
    }

    function reloadBrightness() {
        if (focusedIsPanel)
            backlightFile.reload();
        else
            brightnessLevelFile.reload();
    }
    property bool nightLightOn: false
    // Straight off NetworkManager's D-Bus signals, so the tray icon flips the
    // moment the link does -- this used to be `nmcli device status` every 3s.
    // nm-applet stays for everything interactive (it is NetworkManager's
    // secret agent: the Wi-Fi password and VPN prompts are its dialogs).
    readonly property bool wifiConnected: Networking.devices.values.some(function (device) {
        return device.type === DeviceType.Wifi && device.connected;
    })
    // Last /proc/stat reading; CPU load is the delta to the next one.
    property var cpuSample: null
    property var sink: Pipewire.defaultAudioSink
    property var source: Pipewire.defaultAudioSource

    // On-screen indicator (Osd.qml). It exists only while osdShown; each
    // change restarts the 1.5 s hide timer. osdReady holds it back for the
    // first seconds, when PipeWire and the backlight report their initial
    // levels and would otherwise flash it at every login and bar restart.
    property bool osdReady: false
    property bool osdShown: false
    property string osdKind: "volume"
    property real osdValue: 0
    property bool osdMuted: false

    property var quickSettingsButtons: ({})
    // Where the indicator's right edge goes: centred under the focused
    // screen's quick settings button, measured when it opens (the bar is
    // right-anchored, so the button barely moves while it is up).
    property real osdRightMargin: 14

    function placeOsd() {
        const screen = focusedScreen();
        const button = screen ? quickSettingsButtons[screen.name] : null;
        if (!button || !screen) {
            osdRightMargin = 14;
            return;
        }
        // The bar window starts 14px in from the screen's left edge.
        const center = 14 + button.mapToItem(null, button.width / 2, 0).x;
        osdRightMargin = Math.max(14, screen.width - center - 160);
    }

    function showOsd(kind, value, muted) {
        // Not while quick settings is open: its sliders show the level.
        if (!osdReady || panelOpen)
            return;
        osdKind = kind;
        osdValue = value;
        osdMuted = muted;
        if (!osdShown)
            placeOsd();
        osdShown = true;
        osdHide.restart();
    }

    // The Quickshell screen Hyprland has focused, so the indicator appears
    // where you are looking.
    function focusedScreen() {
        const monitor = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (monitor && screens[i].name === monitor.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    function start(process) {
        if (!process.running)
            process.running = true;
    }

    // Both readouts come from FileView reads of /proc rather than a shell
    // pipeline: the old `top -bn1 | awk; free | awk` was five processes every
    // 3s, and top alone spends ~200ms sampling. The arithmetic lives in
    // bar-logic.mjs, where it is tested.
    function updateCpu(stat) {
        const sample = BarLogic.cpuTimes(stat);
        const percent = BarLogic.cpuPercent(cpuSample, sample);
        if (sample)
            cpuSample = sample;
        if (isNaN(percent))
            return;
        cpuText = percent + "%";
        cpuTooltip = "CPU usage: " + percent + "%";
    }

    function updateMemory(meminfo) {
        const usage = BarLogic.memoryUsage(meminfo);
        if (!usage)
            return;
        const used = usage.usedGiB.toFixed(1);
        const available = usage.availableGiB.toFixed(1);
        // Used only. "Used" already excludes page cache and the GPU driver's
        // buffer pool; the tooltip carries available and total.
        memoryText = used + "G";
        memoryPercent = usage.percent + "%";
        memoryTooltip = "Used: " + used + " GiB (" + usage.percent + "%)"
            + "\nAvailable: " + available + " GiB"
            + "\nTotal: " + usage.totalGiB.toFixed(1) + " GiB"
            + "\nCache and GPU buffer pools count as available:"
            + "\nthe kernel frees them on demand.";
    }

    function refreshWeather() {
        start(weatherProcess);
    }

    // wttr.in hands back "HH:MM:SS" (and sometimes "HH:MM:SS AM"); both reduce
    // to minutes-since-midnight so day/night is a plain numeric compare.
    function weatherIsNight() {
        const now = new Date();
        return BarLogic.isNight(weatherSunrise, weatherSunset,
            now.getHours() * 60 + now.getMinutes());
    }

    function weatherIcon() {
        return BarLogic.weatherIcon(weatherCondition, weatherIsNight());
    }

    // wttr.in reports whatever unit the request resolved to, so read the unit
    // off the string rather than assuming Celsius.
    function weatherCelsius() {
        return BarLogic.weatherCelsius(weatherTemp);
    }

    function weatherColor() {
        return BarLogic.weatherColor(weatherCelsius());
    }

    function weatherTooltip() {
        let body = weatherCondition;
        if (weatherSunrise !== "" && weatherSunset !== "")
            body += "\nSunrise " + weatherSunrise.substring(0, 5)
                + " · Sunset " + weatherSunset.substring(0, 5);
        return body + "\nClick for the full report from wttr.in";
    }

    // CPU and memory share one ramp: neutral until the machine is working,
    // amber under load, red when it is saturated.
    function loadColor(reading) {
        return BarLogic.loadColor(reading);
    }

    function powerProfileText() {
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            return "󰌪";
        if (PowerProfiles.profile === PowerProfile.Performance)
            return "󰓅";
        return "󰾅";
    }

    function powerProfileName() {
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            return "Power Saver";
        if (PowerProfiles.profile === PowerProfile.Performance)
            return "Performance";
        return "Balanced";
    }

    function powerProfileColor() {
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            return Theme.good;
        if (PowerProfiles.profile === PowerProfile.Performance)
            return Theme.warn;
        return Theme.text;
    }

    function togglePowerProfile() {
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced;
        else if (PowerProfiles.profile === PowerProfile.Balanced)
            // Skip a performance step the daemon does not offer, otherwise the
            // write is dropped and the click looks like it did nothing.
            PowerProfiles.profile = PowerProfiles.hasPerformanceProfile
                ? PowerProfile.Performance
                : PowerProfile.PowerSaver;
        else
            PowerProfiles.profile = PowerProfile.PowerSaver;
    }

    function batteryIcon() {
        const device = UPower.displayDevice;
        if (device.state === UPowerDeviceState.Charging
                || device.state === UPowerDeviceState.PendingCharge)
            return "󰂄";
        if (batteryPlugged())
            return "󰚥";
        const percentage = batteryPercentage();
        if (percentage <= 10)
            return "󰂎";
        if (percentage <= 30)
            return "󰁺";
        if (percentage <= 50)
            return "󰁾";
        if (percentage <= 70)
            return "󰂀";
        return "󰁹";
    }

    function batteryPlugged() {
        const state = UPower.displayDevice.state;
        return state === UPowerDeviceState.Charging
            || state === UPowerDeviceState.FullyCharged
            || state === UPowerDeviceState.PendingCharge
            || state === UPowerDeviceState.PendingDischarge;
    }

    function batteryColor() {
        if (batteryPlugged())
            return Theme.good;
        return batteryPercentage() <= 10 ? Theme.bad : Theme.text;
    }

    function batteryPercentage() {
        return Math.round(UPower.displayDevice.percentage * 100);
    }

    function batteryDetails() {
        const device = UPower.displayDevice;
        let details = "Charge: " + batteryPercentage() + "%";
        if (device.timeToEmpty > 0) {
            const hours = Math.floor(device.timeToEmpty / 3600);
            const minutes = Math.round((device.timeToEmpty % 3600) / 60);
            details += "\nEstimated remaining: " + hours + "h " + minutes + "m";
        } else if (device.timeToFull > 0) {
            const hours = Math.floor(device.timeToFull / 3600);
            const minutes = Math.round((device.timeToFull % 3600) / 60);
            details += "\nEstimated until full: " + hours + "h " + minutes + "m";
        }
        if (device.healthSupported)
            details += "\nBattery health: " + Math.round(device.healthPercentage) + "%";
        details += "\nState: " + UPowerDeviceState.toString(device.state);
        return details;
    }

    function audioIcon() {
        if (!sink || !sink.audio || sink.audio.muted)
            return "󰝟";
        const volume = sink.audio.volume;
        if (volume < 0.34)
            return "󰕿";
        if (volume < 0.67)
            return "󰖀";
        return "󰕾";
    }

    // Each workspace keeps its own pastel, so the active pill says which one
    // you are on at a glance. These stay fixed rather than following the
    // wallpaper theme: a colour per number only helps if it never changes.
    function workspaceColor(id) {
        const colors = [
            "#8fb7e8", // 1 blue
            "#8fd6b8", // 2 green
            "#e8a0b5", // 3 pink
            "#c4b5fd", // 4 purple
            "#e8b87a", // 5 amber
            "#7dd3c7", // 6 teal
            "#e89a8f", // 7 coral
            "#e8d78a", // 8 yellow
            "#b9a3e3", // 9 violet
            "#8fd8e8"  // 10 cyan
        ];
        return colors[(id - 1) % colors.length];
    }

    function workspaceForId(id, screen) {
        const monitor = Hyprland.monitorFor(screen);
        const workspaces = Hyprland.workspaces.values;
        for (let index = 0; index < workspaces.length; index++) {
            const workspace = workspaces[index];
            if (workspace.id === id
                    && workspace.monitor
                    && monitor
                    && workspace.monitor.name === monitor.name)
                return workspace;
        }
        return null;
    }

    function activateWorkspace(id) {
        // Quickshell's workspace.activate() sends Hyprland's legacy
        // `dispatch workspace N`, which a Lua config feeds straight to the Lua
        // parser and rejects with "')' expected near '1'" — the click reaches
        // QML fine, the payload is what Hyprland refuses. Send the same
        // dispatcher hyprland.lua's own mod+1..0 binds use instead.
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })");
    }


    settings.watchFiles: true

    IpcHandler {
        target: "bar"

        function toggle(): void {
            root.barVisible = !root.barVisible;
        }

        function refreshWeather(): void {
            root.refreshWeather();
        }

        function togglePanel(): void {
            root.togglePanel();
        }

        function toggleOverview(): void {
            root.overviewOpen = !root.overviewOpen;
        }

        // The switcher: `altTab 1` opens the row and focuses the previous
        // window (or, while the row is up, the next one along), `altTab -1`
        // goes the other way; commit and cancel close it (a card click, Esc).
        function altTab(step: int): void {
            root.altTab(step);
        }

        function altTabCommit(): void {
            root.altTabCommit();
        }

        function altTabCancel(): void {
            root.altTabCancel();
        }

        function refreshBrightness(): void {
            // Only the brightness keys ping this, so only they bring up the
            // indicator -- not hypridle's idle dim, which the 30s reload sees.
            root.brightnessFromKeys = true;
            root.reloadBrightness();
        }

        function refreshNightLight(): void {
            root.start(nightLightStateProcess);
        }

    }

    PwObjectTracker {
        objects: [root.sink, root.source].filter(node => node)
    }

    // Notification server, banners, history, Do Not Disturb (replaces dunst).
    Notifications {
        id: notifications
        // Banners share the top-right corner with the indicator; they step
        // down below it while it is up rather than sitting under it.
        topOffset: root.osdShown ? 74 : 0
    }

    Timer {
        interval: 3000
        running: true
        onTriggered: root.osdReady = true
    }

    Timer {
        id: osdHide
        interval: 1500
        onTriggered: root.osdShown = false
    }

    // PipeWire's own change signals, so it shows for the volume keys and for
    // any app or mixer that moves the default sink -- nothing polls.
    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() {
            root.showOsd("volume", root.sink.audio.volume, root.sink.audio.muted);
        }
        function onMutedChanged() {
            root.showOsd("volume", root.sink.audio.volume, root.sink.audio.muted);
        }
    }

    Connections {
        target: root.source ? root.source.audio : null
        function onMutedChanged() {
            root.showOsd("mic", 1, root.source.audio.muted);
        }
    }

    Process {
        id: brightnessProcess
        onExited: {
            root.reloadBrightness();
            if (root.brightnessPending >= 0)
                root.setBrightness(root.brightnessPending / 100);
        }
    }

    Process {
        id: brightnessRefreshProcess
        command: [Quickshell.env("HOME") + "/.config/brightness.sh", "refresh"]
        onExited: root.reloadBrightness()
    }

    LazyLoader {
        active: root.overviewOpen

        Overview {
            screen: root.focusedScreen()
            shell: root
        }
    }

    LazyLoader {
        active: root.switcherOpen

        AltTab {
            screen: root.focusedScreen()
            shell: root
        }
    }

    LazyLoader {
        active: root.panelOpen

        QuickSettings {
            screen: root.focusedScreen()
            shell: root
            center: notifications
        }
    }

    LazyLoader {
        active: root.osdShown

        Osd {
            screen: root.focusedScreen()
            rightMargin: root.osdRightMargin
            kind: root.osdKind
            value: root.osdValue
            muted: root.osdMuted
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // CPU load is averaged over the whole 3s tick (the delta between two
    // readings), not top's instantaneous sample, so a one-off spike no longer
    // flashes the item amber.
    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: root.updateCpu(text())
    }

    FileView {
        id: memInfoFile
        path: "/proc/meminfo"
        onLoaded: root.updateMemory(text())
    }

    // Docker is gated on the daemon actually running, because docker.service
    // is socket-activated: an unguarded `docker ps` touches /run/docker.sock,
    // which wakes dockerd + containerd (~128 MB) every 15 s and defeats the
    // point of socket activation entirely. dockerd writes /run/docker.pid on
    // start and removes it on exit, so the file existing *is* "the daemon is
    // up" -- read without a process, where this used to be `sh` +
    // `systemctl is-active` every tick. Only with the daemon up does
    // `docker ps` run. "–" means asleep, distinct from the "--" the other
    // items use for "unknown".
    FileView {
        id: dockerPidFile
        path: "/run/docker.pid"
        // Absent is the normal state (daemon asleep), not an error worth a
        // log line every 15 s.
        __printErrors: false
        onLoaded: root.start(dockerProcess)
        onLoadFailed: root.dockerText = "–"
    }

    Process {
        id: dockerProcess
        // A stale pid file (dockerd killed hard) makes `docker ps` fail, which
        // reads as asleep rather than as a count of 0.
        command: ["sh", "-c", "if out=$(docker ps -q 2>/dev/null); then printf '%s\\n' \"$out\" | grep -c . ; else echo –; fi"]
        stdout: StdioCollector {
            onStreamFinished: root.dockerText = text.trim() || "0"
        }
    }

    Process {
        id: weatherProcess
        // %C is the condition name rather than %c's colour emoji, so the bar can
        // draw a Nerd Font glyph that matches every other icon; %S/%s decide
        // whether the clear-sky glyph is a sun or a moon.
        command: ["curl", "-sf", "--max-time", "10", "https://wttr.in/?format=%C|%t|%S|%s"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split("|");
                if (fields.length < 2 || fields[0] === "")
                    return;
                root.weatherCondition = fields[0].trim();
                root.weatherTemp = fields[1].trim();
                root.weatherSunrise = fields.length > 2 ? fields[2].trim() : "";
                root.weatherSunset = fields.length > 3 ? fields[3].trim() : "";
            }
        }
    }

    // Backlight straight from sysfs, the same values brightnessctl reads.
    // The device is found once at startup (intel_backlight here, but it
    // differs by GPU vendor); after that every read is a file read. The
    // brightness keys ping refreshBrightness, so the 30s reload only catches
    // changes made some other way.
    property string backlightDevice: ""

    Process {
        id: backlightDeviceProcess
        command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null | head -n 1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.backlightDevice = text.trim()
        }
    }

    FileView {
        id: backlightMaxFile
        path: root.backlightDevice !== ""
            ? "/sys/class/backlight/" + root.backlightDevice + "/max_brightness" : ""
        onLoaded: root.updateBacklight()
    }

    FileView {
        id: backlightFile
        path: root.backlightDevice !== ""
            ? "/sys/class/backlight/" + root.backlightDevice + "/brightness" : ""
        onLoaded: root.updateBacklight()
    }

    // An external monitor's level, as brightness.sh last read or wrote it.
    FileView {
        id: brightnessLevelFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/initd-brightness/level"
        // Absent until an external monitor has been adjusted or asked once.
        printErrors: false
        onLoaded: root.updateBacklight()
    }

    function updateBacklight() {
        const percent = focusedIsPanel
            ? BarLogic.backlightPercent(backlightFile.text(), backlightMaxFile.text())
            : BarLogic.externalBrightness(brightnessLevelFile.text(), focusedOutput);
        if (isNaN(percent))
            return;
        const changed = backlightText !== percent + "%";
        backlightText = percent + "%";
        backlightValue = percent / 100;
        if (changed && brightnessFromKeys)
            showOsd("brightness", percent / 100, false);
        brightnessFromKeys = false;
    }

    // Night light state is the gammastep process itself, run as the
    // night-light.service user unit (see linux/scripts/night-light-toggle.mjs):
    // on Wayland the gamma table resets when the client exits, so "warm" means
    // "gammastep is running". The toggle script pings `qs ipc call bar
    // refreshNightLight` after every switch — keybind, bulb click or the
    // 07:00/19:00 schedule timer — so the item never lags; the 5-minute timer
    // below only covers gammastep dying on its own.
    Process {
        id: nightLightStateProcess
        command: ["sh", "-c", "pgrep -x gammastep >/dev/null && echo on || echo off"]
        stdout: StdioCollector {
            onStreamFinished: root.nightLightOn = text.trim() === "on"
        }
    }

    // Free space on / (the same btrfs volume as /home here). The one readout
    // that has to be a process: free space lives behind statfs(), which no
    // /proc or /sys file exposes. It changes slowly, so once every 5 minutes.
    Process {
        id: diskProcess
        command: ["df", "-P", "-B1", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const usage = BarLogic.diskUsage(text);
                if (!usage)
                    return;
                root.diskText = BarLogic.formatGiB(usage.availableGiB);
                root.diskPercent = usage.percent + "%";
                root.diskTooltip = "Free: " + BarLogic.formatGiB(usage.availableGiB)
                    + " of " + BarLogic.formatGiB(usage.totalGiB)
                    + "\nUsed: " + usage.percent + "%";
            }
        }
    }

    Timer {
        interval: 300000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.start(diskProcess)
    }

    Process {
        id: nightLightToggleProcess
        command: [Quickshell.env("HOME") + "/.config/night-light-toggle.mjs"]
    }

    Process {
        id: weatherPopupProcess
        command: [Quickshell.env("HOME") + "/.config/weather-popup.mjs"]
    }

    Process {
        id: dockerMenuProcess
        command: [Quickshell.env("HOME") + "/.config/docker-menu.mjs"]
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            memInfoFile.reload();
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        // The panel only: an external monitor is never polled over DDC.
        onTriggered: if (root.focusedIsPanel) backlightFile.reload()
    }

    Timer {
        interval: 300000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.start(nightLightStateProcess)
    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: dockerPidFile.reload()
    }

    Timer {
        interval: 1800000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshWeather()
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel

                required property var modelData
                screen: modelData
                visible: root.barVisible
                implicitHeight: 39
                color: "transparent"
                aboveWindows: true
                focusable: false
                exclusionMode: ExclusionMode.Auto

                anchors {
                    top: true
                    left: true
                    right: true
                }

                margins {
                    top: 4
                    // Must equal general.gaps_out in hyprland.lua, so the island's
                    // edges line up with the tiled windows below it. A window's
                    // reported `at` is gaps_out + border_size because the 1px border
                    // is drawn outside the client area, so its visible edge -- the one
                    // the eye compares against -- lands exactly on gaps_out.
                    left: 14
                    right: 14
                }

                WlrLayershell.namespace: "quickshell-bar"
                WlrLayershell.layer: WlrLayer.Top

                // "Keep awake" in quick settings: an idle inhibitor needs a
                // visible surface, and the bar is the one always mapped.
                IdleInhibitor {
                    window: panel
                    enabled: root.keepAwake
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    // ARGB. Alpha 0xb3 (70%) rather than the old 0xe6 (90%), so the
                    // wallpaper reads through the island. Glyphs stay legible on the
                    // quickshell-bar-blur layer rule in hyprland.lua alone: blurring
                    // the backdrop kills the local contrast that would otherwise fight
                    // the text, so the island does not have to be near-opaque.
                    color: Theme.bar
                    // No outline, matching hyprland.lua's border_size = 0: the
                    // island reads by its fill and the blur behind it.
                    border.width: 0

                    RowLayout {
                        id: barRow
                        anchors {
                            fill: parent
                            // The launchers start the row: 31 px tall in a 35 px row
                            // with a 2 px margin, a hovered one sits 4 px from the
                            // island's top and bottom, so the left inset is 4 to
                            // match. The right end is plain text (the clock), which
                            // wants the wider inset.
                            leftMargin: 4
                            rightMargin: 8
                            topMargin: 2
                            bottomMargin: 2
                        }
                        spacing: 4

                        // Launchers for the apps opened most; everything else is
                        // $mod+d (rofi). Files keeps the nf-md-folder glyph in
                        // workspace 1's blue; the others draw their own app icon.
                        Repeater {
                            model: [
                                { id: "org.gnome.Nautilus", glyph: "\u{f024b}", size: 25, tint: "#8fb7e8" },
                                { id: "org.mozilla.firefox", glyph: "", size: 22, tint: "transparent" },
                                { id: "kitty", glyph: "", size: 22, tint: "transparent" },
                                { id: "com.mitchellh.ghostty", glyph: "", size: 22, tint: "transparent" }
                            ]

                            delegate: AppLauncher {
                                required property var modelData
                                desktopId: modelData.id
                                glyph: modelData.glyph
                                iconSize: modelData.size
                                tint: modelData.tint
                                barWindow: panel
                            }
                        }

                        // The free space between the launchers and the readouts.
                        // The workspaces are not in the row: they are centred on the
                        // island below and only use this to stay clear of both sides.
                        Item {
                            id: freeSpace
                            Layout.fillWidth: true
                        }

                        // Outside: weather.
                        BarGroup {
                            BarItem {
                                icon: root.weatherIcon()
                                iconSize: 27
                                iconSpacing: 8
                                text: root.weatherTemp
                                foreground: root.weatherColor()
                                barWindow: panel
                                tooltipTitle: "Weather"
                                tooltipBody: root.weatherTooltip()
                                clickable: true
                                onClicked: root.start(weatherPopupProcess)
                            }
                        }


                        // Dev.
                        BarGroup {
                            BarItem {
                                icon: "󰡨"
                                // Sizes are per glyph, not shared: Material Design
                                // glyphs fill very different shares of their em box
                                // (the whale ~59%, brightness ~91%), so one shared
                                // size drew them 18-29px tall. Each is tuned to ~22
                                // device px of ink at 1.33x, just above the text's
                                // 17px cap height -- re-measure with grim after
                                // swapping a glyph.
                                iconSize: 28
                                text: root.dockerText
                                barWindow: panel
                                tooltipTitle: "Docker"
                                tooltipBody: (root.dockerText === "–"
                                    ? "Daemon asleep (socket-activated)"
                                    : root.dockerText + " running container"
                                        + (root.dockerText === "1" ? "" : "s"))
                                    + "\nClick to manage containers"
                                clickable: true
                                onClicked: root.start(dockerMenuProcess)
                            }
                        }


                        // System resources: live readouts, hover-only.
                        BarGroup {
                            BarItem {
                                icon: "󰍛"
                                iconSize: 22
                                text: root.cpuText
                                foreground: root.loadColor(root.cpuText)
                                barWindow: panel
                                tooltipTitle: "Processor"
                                tooltipBody: root.cpuTooltip
                            }

                            BarItem {
                                // nf-md-chip, a DIMM module. Not nf-md-speedometer-slow:
                                // that sits one codepoint away from the balanced power
                                // profile's speedometer and the two were indistinguishable
                                // in the bar. Also not nf-md-memory -- the CPU has that one.
                                icon: "󰘚"
                                iconSize: 24
                                text: root.memoryText
                                // The bar shows GiB used, but the ramp still keys off
                                // the percentage -- 9 GiB means nothing without knowing
                                // how much the machine has.
                                foreground: root.loadColor(root.memoryPercent)
                                barWindow: panel
                                tooltipTitle: "Memory"
                                tooltipBody: root.memoryTooltip
                            }

                            BarItem {
                                // nf-md-harddisk. The number is what is *left*,
                                // so the ramp keys off the used percentage, the
                                // same amber-at-70 / red-at-90 as memory.
                                icon: "\u{f02ca}"
                                iconSize: 20
                                iconSpacing: 4
                                text: root.diskText
                                foreground: root.loadColor(root.diskPercent)
                                barWindow: panel
                                tooltipTitle: "Disk"
                                tooltipBody: root.diskTooltip
                            }
                        }


                        // Tray apps (1Password, ...). Wi-Fi and Bluetooth are quick
                        // settings tiles with their own pages now: nm-applet keeps
                        // running headless as NetworkManager's secret agent (the
                        // Wi-Fi password dialog), so its tray icon is filtered out
                        // here, and trayRole() drops blueman's SNI item too.
                        BarGroup {
                            // With no tray apps the group would still cost the row
                            // one extra gap. Keyed off the count, not implicitWidth:
                            // a hidden layout reports 0 and could never come back.
                            visible: trayRepeater.count > 0

                            Repeater {
                                id: trayRepeater
                                model: ScriptModel {
                                    values: SystemTray.items.values.filter(function (item) {
                                        return BarLogic.trayRole(item.id, item.title) === "other";
                                    })
                                }

                                delegate: TrayIcon {
                                    barWindow: panel
                                }
                            }
                        }


                        // Sound.
                        BarGroup {
                            BarItem {
                                id: audioItem

                                icon: root.audioIcon()
                                iconSize: 23
                                text: root.sink && root.sink.audio
                                    ? Math.round(root.sink.audio.volume * 100) + "%"
                                    : "--%"
                                barWindow: panel
                                foreground: root.sink && root.sink.audio && root.sink.audio.muted
                                    ? Theme.textDisabled
                                    : Theme.text
                                tooltipTitle: "Audio"
                                // Deliberately audioMenu's own labeller, so the
                                // tooltip and the picker never disagree about what
                                // the current output is called.
                                tooltipBody: (root.sink
                                        ? "Output: " + audioMenu.deviceLabel(root.sink)
                                        : "No audio output")
                                    + (root.sink && root.sink.audio
                                        ? "\nVolume: " + Math.round(root.sink.audio.volume * 100) + "%"
                                            + (root.sink.audio.muted ? "\nMuted" : "")
                                        : "")
                                    + "\nClick to pick a device"
                                    + (root.sink && root.sink.audio
                                        ? "\nRight-click to " + (root.sink.audio.muted ? "unmute" : "mute")
                                        : "")
                                clickable: true
                                onClicked: audioMenu.open()
                                secondaryClickable: !!(root.sink && root.sink.audio)
                                onSecondaryClicked: {
                                    if (root.sink && root.sink.audio)
                                        root.sink.audio.muted = !root.sink.audio.muted;
                                }

                                AudioMenu {
                                    id: audioMenu
                                    anchorItem: audioItem
                                    barWindow: panel
                                    sink: root.sink
                                }
                            }
                        }


                        // Battery, just left of quick settings. The power profile is a
                        // quick settings tile.
                        BarGroup {
                            BarItem {
                                visible: UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery
                                icon: root.batteryIcon()
                                iconSize: 20
                                iconSpacing: 1
                                text: root.batteryPercentage() + "%"
                                barWindow: panel
                                foreground: root.batteryColor()
                                tooltipTitle: "Battery"
                                tooltipBody: root.batteryDetails()
                            }
                        }


                        // Quick settings. The count is the notification
                        // history; the glyph dims under Do Not Disturb.
                        BarItem {
                            id: quickSettingsButton
                            Component.onCompleted: root.quickSettingsButtons[panel.screen.name] = quickSettingsButton
                            icon: notifications.doNotDisturb ? "\u{f009b}" : "\u{f062e}"
                            text: notifications.history.length > 0 ? String(notifications.history.length) : ""
                            barWindow: panel
                            foreground: root.panelOpen ? Theme.accent
                                : notifications.doNotDisturb ? Theme.textDim : Theme.text
                            clickable: true
                            tooltipTitle: "Quick settings"
                            tooltipBody: notifications.history.length > 0
                                ? notifications.history.length + " notification" + (notifications.history.length === 1 ? "" : "s")
                                : "No notifications"
                            onClicked: root.togglePanel()
                        }


                        BarItem {
                            id: dateItem
                            text: Qt.formatDateTime(clock.date, "ddd, dd MMM  ·  HH:mm")
                            barWindow: panel
                            foreground: Theme.text
                            clickable: true
                            onClicked: calendar.open()

                            CalendarPopup {
                                id: calendar
                                anchorItem: dateItem
                                barWindow: panel
                            }
                        }
                    }

                    RowLayout {
                        id: workspaceRow
                        // Centred on the island, so the pills sit in the middle of
                        // every monitor whatever its width. Clamped into the free
                        // space between the launchers and the readouts (barGap),
                        // so a long row on a narrow screen slides left instead of
                        // running into the weather. The old placement, a 3:1 split
                        // of that free space, sat at ~58% across the Dell.
                        readonly property real barGap: 8
                        readonly property real lowest: barRow.x + freeSpace.x + barGap
                        readonly property real highest: barRow.x + freeSpace.x + freeSpace.width - width - barGap
                        x: Math.max(lowest, Math.min((parent.width - width) / 2, highest))
                        anchors.verticalCenter: parent.verticalCenter
                        height: barRow.height
                        spacing: 4

                        Repeater {
                            model: 10

                            delegate: Rectangle {
                                id: workspaceButton

                                required property int index
                                property int workspaceId: index + 1
                                property var workspace: root.workspaceForId(workspaceId, panel.screen)
                                property bool active: workspace && workspace.active

                                visible: workspace !== null
                                // A circle, the height of every other bar item.
                                Layout.preferredWidth: visible ? 31 : 0
                                Layout.preferredHeight: 31
                                Layout.alignment: Qt.AlignVCenter
                                radius: height / 2
                                color: active
                                    ? root.workspaceColor(workspaceId)
                                    : workspaceHover.hovered ? "#18ffffff" : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: workspaceButton.workspaceId
                                    // Every pastel is light, so one dark label reads on all of them.
                                    color: workspaceButton.active ? "#0b0c10" : Theme.textMuted
                                    font.family: "Inter"
                                    font.pixelSize: 18
                                    font.weight: workspaceButton.active ? Font.Bold : Font.DemiBold
                                }

                                HoverHandler {
                                    id: workspaceHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    acceptedButtons: Qt.LeftButton
                                    onTapped: root.activateWorkspace(workspaceButton.workspaceId)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
