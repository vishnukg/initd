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
    property string netDown: "--"
    property string netUp: "--"
    property string netTooltip: "Network usage unavailable"
    // Last /proc/net/dev reading and when it was taken; the rate is the delta.
    property var netSample: null
    property real netSampleTime: 0
    property string diskPercent: "--%"
    property string diskTooltip: "Disk usage unavailable"
    property string dockerText: "0"
    property string weatherTemp: "--"
    property string weatherCondition: "Unavailable"
    property string weatherSunrise: ""
    property string weatherSunset: ""
    property string backlightText: "--%"
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

    function updateNetwork(procNetDev) {
        const sample = BarLogic.netBytes(procNetDev);
        const now = Date.now();
        const rate = BarLogic.netRate(netSample, sample, (now - netSampleTime) / 1000);
        netSample = sample;
        netSampleTime = now;
        if (!sample) {
            netDown = "--";
            netUp = "--";
            netTooltip = "No network interface";
            return;
        }
        if (!rate)
            return;
        netDown = BarLogic.formatRate(rate.down);
        netUp = BarLogic.formatRate(rate.up);
        netTooltip = "Download: " + netDown + "B/s\nUpload: " + netUp + "B/s"
            + "\nInterfaces: " + sample.interfaces.join(", ");
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
            return "#8fd6b8";
        if (PowerProfiles.profile === PowerProfile.Performance)
            return "#e8b87a";
        return "#e8eaf0";
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
            return "#8fd6b8";
        return batteryPercentage() <= 10 ? "#e0788a" : "#e8eaf0";
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

    function workspaceColor(id) {
        const colors = [
            "#8fb7e8",
            "#8fd6b8",
            "#c4b5fd",
            "#e8b87a",
            "#e8a0b5",
            "#7dd3c7",
            "#e8d78a",
            "#b9a3e3",
            "#e89a8f",
            "#8fd8e8"
        ];
        return colors[(id - 1) % colors.length];
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

        function refreshBrightness(): void {
            backlightFile.reload();
        }

        function refreshNightLight(): void {
            root.start(nightLightStateProcess);
        }

    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
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
        id: netDevFile
        path: "/proc/net/dev"
        onLoaded: root.updateNetwork(text())
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

    function updateBacklight() {
        const percent = BarLogic.backlightPercent(backlightFile.text(), backlightMaxFile.text());
        if (!isNaN(percent))
            backlightText = percent + "%";
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
            netDevFile.reload();
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: backlightFile.reload()
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

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    // ARGB. Alpha 0xb3 (70%) rather than the old 0xe6 (90%), so the
                    // wallpaper reads through the island. Glyphs stay legible on the
                    // quickshell-bar-blur layer rule in hyprland.lua alone: blurring
                    // the backdrop kills the local contrast that would otherwise fight
                    // the text, so the island does not have to be near-opaque.
                    color: "#b30b0c10"
                    // No outline, matching hyprland.lua's border_size = 0: the
                    // island reads by its fill and the blur behind it.
                    border.width: 0

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 8
                            rightMargin: 8
                            topMargin: 2
                            bottomMargin: 2
                        }
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
                                Layout.preferredWidth: visible ? 29 : 0
                                Layout.fillHeight: true
                                Layout.leftMargin: index === 0 ? 4 : 0
                                Layout.rightMargin: index === 9 ? 4 : 0
                                radius: 8
                                color: active
                                    ? root.workspaceColor(workspaceId)
                                    : workspaceHover.hovered ? "#18ffffff" : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: workspaceButton.workspaceId
                                    color: workspaceButton.active ? "#0b0c10" : "#a8abb4"
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

                        Item {
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

                        BarSeparator {}

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

                        BarSeparator {}

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

                            BarItem {
                                // Download/upload across the physical interfaces, from /proc/net/dev
                                // byte counters on the 3s tick (no process). The arrows stand in for
                                // an icon; text sized to its widest value, with tabular digits, keeps the bar from
                                // shifting as the numbers change every tick.
                                text: "\u2193" + root.netDown + "  \u2191" + root.netUp
                                // Up to 999 KB/s, and anything in MB/s below 100, fits;
                                // only >100 MB/s grows the item.
                                textSample: "\u2193888K  \u2191888K"
                                barWindow: panel
                                tooltipTitle: "Network"
                                tooltipBody: root.netTooltip
                            }
                        }

                        BarSeparator {}

                        // Display: brightness, night light, monitor profiles.
                        BarGroup {
                            BarItem {
                                icon: "󰃟"
                                iconSize: 18
                                iconSpacing: 8
                                text: root.backlightText
                                barWindow: panel
                                tooltipTitle: "Display brightness"
                                tooltipBody: "Current brightness: " + root.backlightText
                            }

                            BarItem {
                                // nf-md-lightbulb-outline when off, nf-md-lightbulb-on
                                // (with rays) when warm: the glyph carries the state
                                // as well as the colour. A moon glyph would collide
                                // with the weather item's night variant.
                                icon: root.nightLightOn ? "󰛨" : "󰌶"
                                iconSize: 20
                                barWindow: panel
                                // Amber = warm gamma active. Same "colour is
                                // state" rule as the power profile beside it.
                                foreground: root.nightLightOn ? "#e8b87a" : "#e8eaf0"
                                tooltipTitle: "Night light"
                                tooltipBody: (root.nightLightOn ? "On (4500 K)" : "Off")
                                    + "\nSchedule: 19:00 – 07:00"
                                    + "\nClick to toggle"
                                clickable: true
                                onClicked: root.start(nightLightToggleProcess)
                            }

                            BarItem {
                                id: displayItem

                                icon: "󰍹"
                                iconSize: 20
                                iconSpacing: 8
                                text: displayMenu.enabledCount > 0
                                    ? String(displayMenu.enabledCount)
                                    : "--"
                                barWindow: panel
                                tooltipTitle: "Displays"
                                tooltipBody: (displayMenu.activeProfile !== ""
                                        ? "Profile: " + displayMenu.activeProfile
                                        : "No profile applied")
                                    + displayMenu.monitorSummary()
                                    + "\nClick to switch profile"
                                clickable: true
                                onClicked: displayMenu.open()

                                DisplayMenu {
                                    id: displayMenu
                                    anchorItem: displayItem
                                    barWindow: panel
                                }
                            }
                        }

                        BarSeparator {}

                        // Connections: Wi-Fi, Bluetooth, then the remaining tray apps.
                        BarGroup {
                            // Wi-Fi, then Bluetooth, then every other tray item
                            // (1Password, ...): Bluetooth is drawn natively now, so
                            // the tray is split around it to keep the order it had
                            // as a blueman icon. trayRole() also drops blueman's own
                            // SNI item, if one is still registered.
                            Repeater {
                                model: ScriptModel {
                                    values: SystemTray.items.values.filter(function (item) {
                                        return BarLogic.trayRole(item.id, item.title) === "network";
                                    })
                                }

                                delegate: TrayIcon {
                                    barWindow: panel
                                    wifiConnected: root.wifiConnected
                                }
                            }

                            BarItem {
                                id: bluetoothItem

                                visible: !!Bluetooth.defaultAdapter
                                // Papirus, the same icon set as the Wi-Fi icon beside
                                // it: nf-md-bluetooth's hairline B read thinner than
                                // every neighbour. The theme has no "connected"
                                // variant, so state is colour -- blue while a device
                                // is connected, dimmed and crossed out when off.
                                iconSource: "file:///usr/share/icons/Papirus-Dark/16x16/panel/"
                                    + (bluetoothMenu.powered ? "blueman-tray.svg" : "blueman-tray-disabled.svg")
                                // ~25 device px against the others' ~22: a B is narrow,
                                // so at matched height it carried half the ink of its
                                // Wi-Fi and 1Password neighbours and read as smaller.
                                iconSize: 19
                                barWindow: panel
                                foreground: !bluetoothMenu.powered ? "#52566a"
                                    : bluetoothMenu.connectedDevices.length > 0 ? "#8fb7e8"
                                    : "#e8eaf0"
                                tooltipTitle: "Bluetooth"
                                tooltipBody: bluetoothMenu.summary() + "\nClick for devices"
                                clickable: true
                                onClicked: bluetoothMenu.open()

                                BluetoothMenu {
                                    id: bluetoothMenu
                                    anchorItem: bluetoothItem
                                    barWindow: panel
                                }
                            }

                            Repeater {
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

                        BarSeparator {}

                        // Power: profile next to the battery it governs.
                        BarGroup {
                            BarItem {
                                icon: root.powerProfileText()
                                iconSize: 22
                                barWindow: panel
                                foreground: root.powerProfileColor()
                                tooltipTitle: "Power profile"
                                tooltipBody: root.powerProfileName()
                                    + "\nClick to switch"
                                clickable: true
                                onClicked: root.togglePowerProfile()
                            }

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

                        BarSeparator {}

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
                                    ? "#52566a"
                                    : "#e8eaf0"
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

                        BarSeparator {}

                        BarItem {
                            id: dateItem
                            text: Qt.formatDateTime(clock.date, "ddd, dd MMM  ·  HH:mm")
                            barWindow: panel
                            foreground: "#e8eaf0"
                            clickable: true
                            onClicked: calendar.open()

                            CalendarPopup {
                                id: calendar
                                anchorItem: dateItem
                                barWindow: panel
                            }
                        }
                    }
                }
            }
        }
    }
}
