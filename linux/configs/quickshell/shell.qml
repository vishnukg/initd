//@ pragma UseQApplication

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland

ShellRoot {
    id: root

    property bool barVisible: true
    property string cpuText: "--%"
    property string cpuTooltip: "CPU usage unavailable"
    property string memoryText: "--G"
    property string memoryPercent: "--%"
    property string memoryTooltip: "Memory usage unavailable"
    property string dockerText: "0"
    property string weatherTemp: "--"
    property string weatherCondition: "Unavailable"
    property string weatherSunrise: ""
    property string weatherSunset: ""
    property string backlightText: "--%"
    property bool nightLightOn: false
    property var sink: Pipewire.defaultAudioSink

    function start(process) {
        if (!process.running)
            process.running = true;
    }

    function refreshWeather() {
        start(weatherProcess);
    }

    // wttr.in hands back "HH:MM:SS" (and sometimes "HH:MM:SS AM"); both reduce
    // to minutes-since-midnight so day/night is a plain numeric compare.
    function clockMinutes(value) {
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

    function weatherIsNight() {
        const sunrise = clockMinutes(weatherSunrise);
        const sunset = clockMinutes(weatherSunset);
        if (sunrise < 0 || sunset < 0)
            return false;
        const now = new Date();
        const minutes = now.getHours() * 60 + now.getMinutes();
        return minutes < sunrise || minutes >= sunset;
    }

    // WWO condition names are a fixed vocabulary ("Patchy light rain with
    // thunder", "Moderate or heavy sleet showers", ...), so keyword tests in
    // severity order cover the whole set without a 48-entry lookup table.
    function weatherIcon() {
        const condition = weatherCondition.toLowerCase();
        const night = weatherIsNight();
        if (condition.indexOf("thunder") >= 0)
            return condition.indexOf("rain") >= 0 || condition.indexOf("snow") >= 0
                ? "󰙾"
                : "󰖓";
        if (condition.indexOf("ice pellets") >= 0 || condition.indexOf("hail") >= 0)
            return "󰖒";
        if (condition.indexOf("fog") >= 0)
            return "󰖑";
        if (condition.indexOf("mist") >= 0 || condition.indexOf("haze") >= 0)
            return "󰼰";
        if (condition.indexOf("sleet") >= 0 || condition.indexOf("freezing") >= 0)
            return "󰙿";
        if (condition.indexOf("blizzard") >= 0 || condition.indexOf("heavy snow") >= 0)
            return "󰼶";
        if (condition.indexOf("snow") >= 0)
            return condition.indexOf("patchy") >= 0 ? "󰼵" : "󰖘";
        if (condition.indexOf("torrential") >= 0 || condition.indexOf("heavy rain") >= 0)
            return "󰖖";
        if (condition.indexOf("rain") >= 0 || condition.indexOf("drizzle") >= 0
                || condition.indexOf("shower") >= 0)
            return condition.indexOf("patchy") >= 0 ? "󰼳" : "󰖗";
        if (condition.indexOf("partly") >= 0)
            return night ? "󰼱" : "󰖕";
        if (condition.indexOf("cloud") >= 0 || condition.indexOf("overcast") >= 0)
            return "󰖐";
        if (condition.indexOf("sunny") >= 0)
            return "󰖙";
        if (condition.indexOf("clear") >= 0)
            return night ? "󰖔" : "󰖙";
        return "󰼯";
    }

    // wttr.in reports whatever unit the request resolved to, so read the unit
    // off the string rather than assuming Celsius.
    function weatherCelsius() {
        const match = /(-?\d+(?:\.\d+)?)/.exec(weatherTemp);
        if (!match)
            return NaN;
        const value = parseFloat(match[1]);
        return /F/i.test(weatherTemp) ? (value - 32) * 5 / 9 : value;
    }

    // Mild weather says nothing, so it stays flat: colour only appears once the
    // reading is cold enough or hot enough to be worth noticing, deepening as
    // it gets further from comfortable.
    function weatherColor() {
        const celsius = weatherCelsius();
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
        const percent = parseInt(reading, 10);
        if (isNaN(percent))
            return "#e8eaf0";
        if (percent >= 90)
            return "#e0788a";
        if (percent >= 70)
            return "#e8b87a";
        return "#e8eaf0";
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
            root.start(backlightProcess);
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

    Process {
        id: metricsProcess
        // Busy time is everything top does not report as idle *or* iowait: a
        // plain 100-idle counts disk waits as CPU load and pins the readout
        // near 40% while the machine is idle. Labels are matched instead of
        // column positions because top drops columns it has no data for.
        command: ["sh", "-c", "LC_ALL=C top -bn1 | awk '/^%Cpu/ { idle = 0; for (i = 2; i <= NF; i++) if ($i ~ /^(id|wa),?$/) idle += $(i-1); cpu = 100 - idle } END { printf \"%.0f|\", cpu }'; free -m | awk '/^Mem:/ { printf \"%.0f|%.1f|%.1f\\n\", $3*100/$2, $3/1024, $2/1024 }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split("|");
                if (fields.length !== 4)
                    return;
                root.cpuText = fields[0] + "%";
                root.cpuTooltip = "CPU usage: " + fields[0] + "%";
                root.memoryText = fields[2] + "G";
                root.memoryPercent = fields[1] + "%";
                root.memoryTooltip = "Memory used: " + fields[2] + " GiB / " + fields[3]
                    + " GiB (" + fields[1] + "%)";
            }
        }
    }

    Process {
        id: dockerProcess
        // Guarded on docker.service being up, because docker.service is
        // socket-activated: an unguarded `docker ps` touches /run/docker.sock,
        // which wakes dockerd + containerd (~128 MB) every 15 s and defeats the
        // point of socket activation entirely. "–" means the daemon is asleep,
        // which is distinct from the "--" the other items use for "unknown".
        command: ["sh", "-c", "systemctl is-active --quiet docker.service && docker ps -q 2>/dev/null | wc -l || echo -"]
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

    Process {
        id: backlightProcess
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | awk -F, 'NR == 1 { gsub(/%/, \"\", $4); print $4 }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.backlightText = text.trim() + "%";
            }
        }
    }

    // Night light state is the gammastep process itself (see
    // linux/scripts/night-light-toggle.sh): on Wayland the gamma table resets
    // when the client exits, so "warm" means "gammastep is running". The
    // toggle script pings `qs ipc call bar refreshNightLight` after every
    // switch, so the keybind and the bar item never disagree; the 30s timer
    // only covers gammastep dying on its own.
    Process {
        id: nightLightStateProcess
        command: ["sh", "-c", "pgrep -x gammastep >/dev/null && echo on || echo off"]
        stdout: StdioCollector {
            onStreamFinished: root.nightLightOn = text.trim() === "on"
        }
    }

    Process {
        id: nightLightToggleProcess
        command: [Quickshell.env("HOME") + "/.config/night-light-toggle.sh"]
    }

    Process {
        id: weatherPopupProcess
        command: [Quickshell.env("HOME") + "/.config/weather-popup.sh"]
    }

    Process {
        id: dockerMenuProcess
        command: [Quickshell.env("HOME") + "/.config/docker-menu.sh"]
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.start(metricsProcess)
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.start(backlightProcess);
            root.start(nightLightStateProcess);
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.start(dockerProcess)
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
                    border.width: 1
                    // Lifted with the alpha: once the fill stopped being near-opaque
                    // the old 0x18 edge disappeared against light regions of the
                    // wallpaper and the island lost its shape.
                    border.color: "#2effffff"

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

                        BarItem {
                            icon: "󰡨"
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

                        BarItem {
                            icon: root.weatherIcon()
                            iconSize: 26
                            text: root.weatherTemp
                            foreground: root.weatherColor()
                            barWindow: panel
                            tooltipTitle: "Weather"
                            tooltipBody: root.weatherTooltip()
                            clickable: true
                            onClicked: root.start(weatherPopupProcess)
                        }

                        BarItem {
                            icon: root.powerProfileText()
                            iconSize: 27
                            barWindow: panel
                            foreground: root.powerProfileColor()
                            tooltipTitle: "Power profile"
                            tooltipBody: root.powerProfileName()
                                + "\nClick to switch"
                            clickable: true
                            onClicked: root.togglePowerProfile()
                        }

                        BarItem {
                            icon: "󰍛"
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
                            icon: "󰃟"
                            // Same reason as the monitor glyph next to it:
                            // nf-md-brightness-6 draws small at the shared
                            // 21px and needs a couple of pixels back.
                            iconSize: 24
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
                            iconSize: 24
                            barWindow: panel
                            // Amber = warm gamma active. Same "colour is
                            // state" rule as the power profile beside it.
                            foreground: root.nightLightOn ? "#e8b87a" : "#e8eaf0"
                            tooltipTitle: "Night light"
                            tooltipBody: (root.nightLightOn ? "On (4500 K)" : "Off")
                                + "\nClick to toggle"
                            clickable: true
                            onClicked: root.start(nightLightToggleProcess)
                        }

                        BarItem {
                            id: displayItem

                            icon: "󰍹"
                            // nf-md-monitor sits visually smaller than the
                            // other glyphs at the shared 21px, so it gets a
                            // couple of pixels back to match them.
                            iconSize: 24
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

                        Repeater {
                            model: SystemTray.items

                            delegate: Item {
                                id: trayItem

                                required property var modelData
                                property string identity: (modelData.id + " " + modelData.title).toLowerCase()
                                property bool networkApplet: identity.indexOf("networkmanager") !== -1
                                    || identity.indexOf("nm-applet") !== -1
                                property bool bluetoothApplet: identity.indexOf("blueman") !== -1
                                Layout.preferredWidth: 29
                                Layout.fillHeight: true

                                Image {
                                    anchors.centerIn: parent
                                    width: 19
                                    height: 19
                                    source: trayItem.networkApplet
                                        ? "file:///usr/share/icons/Papirus-Dark/16x16/devices/network-wireless.svg"
                                        : trayItem.bluetoothApplet
                                            ? "file:///usr/share/icons/Papirus-Dark/16x16/devices/bluetooth.svg"
                                            : trayItem.modelData.icon
                                    sourceSize: Qt.size(width, height)
                                }

                                QsMenuAnchor {
                                    id: trayMenu
                                    menu: trayItem.modelData.menu
                                    anchor.item: trayItem
                                }

                                TrayMenu {
                                    id: modernMenu
                                    anchorItem: trayItem
                                    barWindow: panel
                                    menu: trayItem.modelData.menu
                                }

                                HoverHandler {
                                    id: trayHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    acceptedButtons: Qt.LeftButton
                                    onTapped: {
                                        if (trayItem.networkApplet || trayItem.bluetoothApplet) {
                                            modernMenu.open();
                                        } else if (trayItem.modelData.hasMenu
                                                && trayItem.modelData.onlyMenu) {
                                            trayMenu.open();
                                        } else {
                                            trayItem.modelData.activate();
                                        }
                                    }
                                }

                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: {
                                        if (trayItem.networkApplet || trayItem.bluetoothApplet) {
                                            modernMenu.open();
                                        } else if (trayItem.modelData.hasMenu) {
                                            trayMenu.open();
                                        } else {
                                            trayItem.modelData.secondaryActivate();
                                        }
                                    }
                                }

                            }
                        }

                        BarItem {
                            visible: UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery
                            icon: root.batteryIcon()
                            text: root.batteryPercentage() + "%"
                            barWindow: panel
                            foreground: root.batteryColor()
                            tooltipTitle: "Battery"
                            tooltipBody: root.batteryDetails()
                        }

                        BarItem {
                            id: audioItem

                            icon: root.audioIcon()
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

                        BarItem {
                            id: dateItem
                            text: Qt.formatDateTime(clock.date, "ddd, dd MMM  ·  HH:mm")
                            barWindow: panel
                            foreground: "#e8eaf0"
                            background: "#0fffffff"
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
