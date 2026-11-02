import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Wayland
import "bar-logic.mjs" as BarLogic

// Quick settings, ChromeOS/macOS style: toggles, volume and brightness, the
// playing media, power actions and the notification history, in one frosted
// sheet under the bar's right end. Opened by the bar's button or $mod+a
// (`qs ipc call bar togglePanel`); Esc or a click anywhere else closes it.
// shell.qml creates it through a LazyLoader only while open.
PanelWindow {
    id: sheet

    required property var shell
    // The Notifications scope. Not called `notifications`: inside the
    // LazyLoader that creates this, `notifications: notifications` would bind
    // the property to itself (undefined) before reaching shell.qml's id.
    required property var center

    readonly property var sink: shell.sink
    readonly property var player: {
        const players = Mpris.players.values;
        let fallback = null;
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying)
                return players[i];
            if (!fallback && players[i].trackTitle)
                fallback = players[i];
        }
        return fallback;
    }
    readonly property var adapter: Bluetooth.defaultAdapter

    // "main", or a detail page opened by a tile's arrow: "wifi" | "bluetooth".
    property string page: "main"
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wifiNetworks: wifiDevice ? BarLogic.wifiNetworkList(wifiDevice.networks.values) : []
    readonly property var btDevices: Bluetooth.devices.values
        .filter(d => d.paired || d.bonded)
        .sort(BarLogic.compareBluetoothDevices)

    // Scan for networks only while the Wi-Fi page is open, never in the
    // background, and stop when the sheet goes away.
    onPageChanged: if (wifiDevice) wifiDevice.scannerEnabled = page === "wifi"
    Component.onDestruction: if (wifiDevice) wifiDevice.scannerEnabled = false

    function back() {
        if (page !== "main")
            page = "main";
        else
            close();
    }

    function btTag(device) {
        if (device.state === BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (device.connected && device.batteryAvailable) {
            const percent = BarLogic.batteryPercent(device.battery);
            if (!isNaN(percent))
                return "Connected  ·  " + percent + "%";
        }
        return device.connected ? "Connected" : "";
    }

    function btToggle(device) {
        if (device.state === BluetoothDeviceState.Connecting
                || device.state === BluetoothDeviceState.Disconnecting)
            return;
        if (device.connected)
            device.disconnect();
        else
            device.connect();
    }

    function wifiTag(network) {
        if (network.connected)
            return "Connected";
        if (network.stateChanging)
            return "Connecting…";
        return network.known ? "Saved" : "";
    }
    // Power actions need a second click within 3 s, so a stray click never
    // shuts the machine down.
    property string armed: ""

    function close() {
        shell.panelOpen = false;
    }

    function run(command) {
        Quickshell.execDetached(command);
        close();
    }

    function power(action, command) {
        if (armed === action) {
            run(command);
            return;
        }
        armed = action;
        disarm.restart();
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 420
    implicitHeight: body.implicitHeight + 36

    anchors {
        top: true
        right: true
    }

    margins {
        top: 52
        right: 14
    }

    WlrLayershell.namespace: "quickshell-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive so Esc reaches it; Hyprland's own binds still work, and the
    // focus grab below closes the sheet on any click outside it.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Monitor profiles (hyprmoncfg). Lives as long as the sheet: one status
    // call per opening.
    Displays {
        id: displays
    }

    HyprlandFocusGrab {
        windows: [sheet]
        active: true
        onCleared: sheet.close()
    }

    FileView {
        id: rotateFile
        property bool on: false
        path: Quickshell.env("HOME") + "/.local/state/initd/wallpaper-rotate"
        onLoaded: on = true
        onLoadFailed: on = false
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: sheet.armed = ""
    }

    Rectangle {
        anchors.fill: parent
        radius: 26
        color: Theme.menu
        border.width: 1
        border.color: "#24ffffff"

        focus: true
        Keys.onEscapePressed: sheet.back()

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                visible: sheet.page === "main"
                spacing: 14

                // --- Header: battery, then lock and power ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: sheet.shell.batteryIcon()
                        color: sheet.shell.batteryColor()
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 18
                        visible: UPower.displayDevice.isLaptopBattery
                    }

                    Text {
                        Layout.fillWidth: true
                        text: UPower.displayDevice.isLaptopBattery
                            ? sheet.shell.batteryPercentage() + "%" + (sheet.shell.batteryPlugged() ? "  ·  charging" : "")
                            : Qt.formatDateTime(sheet.shell.clockDate, "dddd, d MMMM")
                        color: Theme.textMuted
                        font.family: "Inter"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    RoundButton {
                        glyph: "\u{f033e}"
                        tip: "Lock"
                        onClicked: sheet.run(["loginctl", "lock-session"])
                    }

                    RoundButton {
                        glyph: "\u{f0425}"
                        tip: "Power"
                        active: powerRow.visible
                        onClicked: powerRow.visible = !powerRow.visible
                    }
                }

                // Power actions, revealed by the power button; each needs a
                // confirming second click.
                RowLayout {
                    id: powerRow
                    Layout.fillWidth: true
                    visible: false
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "suspend", label: "Sleep", glyph: "\u{f04b2}", command: ["systemctl", "suspend"] },
                            { id: "logout", label: "Log out", glyph: "\u{f0343}", command: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
                            { id: "reboot", label: "Restart", glyph: "\u{f0709}", command: ["systemctl", "reboot"] },
                            { id: "poweroff", label: "Shut down", glyph: "\u{f0425}", command: ["systemctl", "poweroff"] },
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isArmed: sheet.armed === modelData.id
                            Layout.fillWidth: true
                            implicitHeight: 54
                            radius: 16
                            color: isArmed ? Theme.bad : powerHover.hovered ? "#24ffffff" : "#12ffffff"

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.glyph
                                    color: isArmed ? Theme.onAccent : Theme.text
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 18
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: isArmed ? "Confirm" : modelData.label
                                    color: isArmed ? Theme.onAccent : Theme.textMuted
                                    font.family: "Inter"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }

                            HoverHandler {
                                id: powerHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sheet.power(modelData.id, modelData.command)
                            }
                        }
                    }
                }

                // --- Toggles ---
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 8

                    Tile {
                        glyph: Networking.wifiEnabled ? "\u{f05a9}" : "\u{f05aa}"
                        title: "Wi-Fi"
                        detail: !Networking.wifiEnabled ? "Off" : sheet.shell.wifiConnected ? "Connected" : "Not connected"
                        on: Networking.wifiEnabled
                        expandable: true
                        onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                        onExpanded: sheet.page = "wifi"
                    }

                    Tile {
                        glyph: sheet.adapter && sheet.adapter.enabled ? "\u{f00af}" : "\u{f00b2}"
                        title: "Bluetooth"
                        detail: !sheet.adapter ? "Unavailable" : sheet.adapter.enabled ? "On" : "Off"
                        on: !!sheet.adapter && sheet.adapter.enabled
                        expandable: true
                        onClicked: if (sheet.adapter) sheet.adapter.enabled = !sheet.adapter.enabled
                        onExpanded: sheet.page = "bluetooth"
                    }

                    Tile {
                        glyph: "\u{f0335}"
                        title: "Night light"
                        detail: sheet.shell.nightLightOn ? "Warm" : "Off"
                        on: sheet.shell.nightLightOn
                        onClicked: sheet.shell.toggleNightLight()
                    }

                    Tile {
                        glyph: sheet.center.doNotDisturb ? "\u{f009b}" : "\u{f009a}"
                        title: "Do Not Disturb"
                        detail: sheet.center.doNotDisturb ? "On" : "Off"
                        on: sheet.center.doNotDisturb
                        onClicked: sheet.center.doNotDisturb = !sheet.center.doNotDisturb
                    }

                    Tile {
                        glyph: sheet.shell.powerProfileText()
                        title: "Power mode"
                        detail: sheet.shell.powerProfileName()
                        on: true
                        onClicked: sheet.shell.togglePowerProfile()
                    }

                    Tile {
                        glyph: "\u{f0e09}"
                        title: "Wallpaper"
                        detail: "Choose…"
                        on: false
                        onClicked: sheet.run(["node", Quickshell.env("HOME") + "/.config/wallpaper.mjs", "pick"])
                    }

                    Tile {
                        glyph: "\u{f0456}"
                        title: "Rotate wallpaper"
                        detail: rotateFile.on ? "Every hour" : "Off"
                        on: rotateFile.on
                        onClicked: {
                            rotateFile.on = !rotateFile.on;
                            Quickshell.execDetached(["node", Quickshell.env("HOME") + "/.config/wallpaper.mjs",
                                "rotation", rotateFile.on ? "on" : "off"]);
                        }
                    }

                    Tile {
                        glyph: "\u{f0176}"
                        title: "Keep awake"
                        detail: sheet.shell.keepAwake ? "No auto-lock" : "Off"
                        on: sheet.shell.keepAwake
                        onClicked: sheet.shell.keepAwake = !sheet.shell.keepAwake
                    }

                    Tile {
                        Layout.columnSpan: 2
                        glyph: "\u{f0379}"
                        title: "Displays"
                        detail: displays.activeProfile !== "" ? displays.activeProfile
                            : displays.enabledCount + (displays.enabledCount === 1 ? " display" : " displays")
                        on: false
                        expandable: true
                        onClicked: sheet.page = "displays"
                        onExpanded: sheet.page = "displays"
                    }
                }

                // --- Sliders ---
                SliderRow {
                    Layout.fillWidth: true
                    glyph: sheet.shell.audioIcon()
                    value: sheet.sink && sheet.sink.audio ? sheet.sink.audio.volume : 0
                    muted: !sheet.sink || !sheet.sink.audio || sheet.sink.audio.muted
                    onGlyphClicked: if (sheet.sink && sheet.sink.audio) sheet.sink.audio.muted = !sheet.sink.audio.muted
                    onMoved: v => {
                        if (sheet.sink && sheet.sink.audio) {
                            sheet.sink.audio.muted = false;
                            sheet.sink.audio.volume = v;
                        }
                    }
                }

                SliderRow {
                    Layout.fillWidth: true
                    glyph: "\u{f00df}"
                    value: sheet.shell.backlightValue
                    minimum: 0.02
                    onMoved: v => sheet.shell.setBrightness(v)
                }

                // --- Now playing ---
                Rectangle {
                    Layout.fillWidth: true
                    visible: sheet.player !== null
                    implicitHeight: 72
                    radius: 18
                    color: "#12ffffff"

                    RowLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 52
                            radius: 12
                            color: "#14ffffff"
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: sheet.player ? sheet.player.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 104
                                sourceSize.height: 104
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: sheet.player ? (sheet.player.trackTitle || "Unknown title") : ""
                                color: Theme.text
                                elide: Text.ElideRight
                                font.family: "Inter"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                text: sheet.player ? (sheet.player.trackArtist || sheet.player.identity) : ""
                                color: Theme.textMuted
                                elide: Text.ElideRight
                                font.family: "Inter"
                                font.pixelSize: 12
                            }
                        }

                        RoundButton {
                            glyph: "\u{f04ae}"
                            onClicked: if (sheet.player) sheet.player.previous()
                        }

                        RoundButton {
                            glyph: sheet.player && sheet.player.isPlaying ? "\u{f03e4}" : "\u{f040a}"
                            active: true
                            onClicked: if (sheet.player) sheet.player.togglePlaying()
                        }

                        RoundButton {
                            glyph: "\u{f04ad}"
                            onClicked: if (sheet.player) sheet.player.next()
                        }
                    }
                }

                // --- Notifications ---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2

                    Text {
                        Layout.fillWidth: true
                        text: "Notifications"
                        color: Theme.text
                        font.family: "Inter"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    Text {
                        visible: sheet.center.history.length > 0
                        text: "Clear all"
                        color: clearHover.hovered ? Theme.text : Theme.accent
                        font.family: "Inter"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold

                        HoverHandler {
                            id: clearHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sheet.center.clearAll()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: sheet.center.history.length === 0
                    topPadding: 6
                    bottomPadding: 10
                    horizontalAlignment: Text.AlignHCenter
                    text: "You're all caught up"
                    color: Theme.textDim
                    font.family: "Inter"
                    font.pixelSize: 13
                }

                Flickable {
                    Layout.fillWidth: true
                    visible: sheet.center.history.length > 0
                    implicitHeight: Math.min(list.implicitHeight, 340)
                    contentHeight: list.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: list
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: ScriptModel {
                                values: sheet.center.history
                            }

                            delegate: NotificationCard {
                                required property var modelData
                                notification: modelData
                                width: list.width
                                compact: true
                                color: "#12ffffff"
                                border.width: 0
                            }
                        }
                    }
                }
            }

            // --- Wi-Fi page ---
            ColumnLayout {
                Layout.fillWidth: true
                visible: sheet.page === "wifi"
                spacing: 8

                PageHeader {
                    title: "Wi-Fi"
                    on: Networking.wifiEnabled
                    onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                    onBack: sheet.page = "main"
                }

                Text {
                    Layout.fillWidth: true
                    visible: !Networking.wifiEnabled || sheet.wifiNetworks.length === 0
                    topPadding: 10
                    bottomPadding: 10
                    horizontalAlignment: Text.AlignHCenter
                    text: !Networking.wifiEnabled ? "Wi-Fi is off" : "Looking for networks…"
                    color: Theme.textDim
                    font.family: "Inter"
                    font.pixelSize: 13
                }

                Flickable {
                    Layout.fillWidth: true
                    visible: Networking.wifiEnabled && sheet.wifiNetworks.length > 0
                    implicitHeight: Math.min(networkList.implicitHeight, 384)
                    contentHeight: networkList.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: networkList
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: ScriptModel {
                                values: sheet.wifiNetworks
                            }

                            delegate: ListRow {
                                required property var modelData
                                width: networkList.width
                                glyph: BarLogic.wifiSignalIcon(modelData.signalStrength)
                                label: modelData.name
                                tag: sheet.wifiTag(modelData)
                                trailing: modelData.security === WifiSecurityType.Open ? "" : "\u{f033e}"
                                highlighted: modelData.connected
                                // A secured network not yet saved: NetworkManager
                                // asks nm-applet (still running as its secret
                                // agent) for the password in a dialog.
                                onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                            }
                        }
                    }
                }

                ListRow {
                    Layout.fillWidth: true
                    glyph: "\u{f0493}"
                    label: "Network settings…"
                    onClicked: sheet.run(["nm-connection-editor"])
                }
            }

            // --- Bluetooth page ---
            ColumnLayout {
                Layout.fillWidth: true
                visible: sheet.page === "bluetooth"
                spacing: 8

                PageHeader {
                    title: "Bluetooth"
                    on: !!sheet.adapter && sheet.adapter.enabled
                    onToggled: if (sheet.adapter) sheet.adapter.enabled = !sheet.adapter.enabled
                    onBack: sheet.page = "main"
                }

                Text {
                    Layout.fillWidth: true
                    visible: !sheet.adapter || !sheet.adapter.enabled || sheet.btDevices.length === 0
                    topPadding: 10
                    bottomPadding: 10
                    horizontalAlignment: Text.AlignHCenter
                    text: !sheet.adapter ? "No Bluetooth adapter"
                        : !sheet.adapter.enabled ? "Bluetooth is off" : "No paired devices"
                    color: Theme.textDim
                    font.family: "Inter"
                    font.pixelSize: 13
                }

                Flickable {
                    Layout.fillWidth: true
                    visible: !!sheet.adapter && sheet.adapter.enabled && sheet.btDevices.length > 0
                    implicitHeight: Math.min(deviceList.implicitHeight, 384)
                    contentHeight: deviceList.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: deviceList
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: ScriptModel {
                                values: sheet.btDevices
                            }

                            delegate: ListRow {
                                required property var modelData
                                width: deviceList.width
                                glyph: BarLogic.bluetoothDeviceIcon(modelData.icon)
                                label: modelData.name || modelData.address
                                tag: sheet.btTag(modelData)
                                highlighted: modelData.connected
                                onClicked: sheet.btToggle(modelData)
                            }
                        }
                    }
                }

                ListRow {
                    Layout.fillWidth: true
                    glyph: "\u{f0493}"
                    label: "Bluetooth settings…"
                    onClicked: sheet.run(["blueman-manager"])
                }
            }

            // --- Displays page ---
            ColumnLayout {
                Layout.fillWidth: true
                visible: sheet.page === "displays"
                spacing: 6

                PageHeader {
                    title: "Displays"
                    showSwitch: false
                    onBack: sheet.page = "main"
                }

                SectionLabel { text: "Connected" }

                Repeater {
                    model: displays.monitors.filter(m => m.enabled)

                    delegate: ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        glyph: displays.monitorIcon(modelData)
                        label: displays.monitorLabel(modelData)
                        tag: displays.monitorTag(modelData)
                        interactive: false
                    }
                }

                SectionLabel {
                    text: "Profiles"
                    visible: displays.profiles.length > 0
                }

                // hyprmoncfg validates before it commits; a profile it cannot
                // lay out (saved against another monitor) fails with a
                // notification saying why, and the layout stays as it was.
                Repeater {
                    model: displays.profiles

                    delegate: ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        glyph: modelData.active ? "\u{f012c}" : "\u{f0379}"
                        label: modelData.name
                        tag: displays.profileTag(modelData)
                        highlighted: modelData.active
                        onClicked: {
                            displays.applyProfile(modelData.name);
                            // The layout is about to change under the sheet.
                            sheet.close();
                        }
                    }
                }

                ListRow {
                    Layout.fillWidth: true
                    glyph: "\u{f0493}"
                    label: "Arrange displays…"
                    tag: "hyprmoncfg tui: modes, positions, new profiles"
                    onClicked: sheet.run(["kitty", "-e", "hyprmoncfg", "tui"])
                }
            }

        }
    }

    // --- Pieces ---

    component RoundButton: Rectangle {
        id: round
        property string glyph: ""
        property string tip: ""
        property bool active: false
        signal clicked()

        implicitWidth: 38
        implicitHeight: 38
        radius: 19
        color: active ? Theme.accent : roundHover.hovered ? "#24ffffff" : "#12ffffff"

        Text {
            anchors.centerIn: parent
            text: round.glyph
            color: round.active ? Theme.onAccent : Theme.text
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 18
        }

        HoverHandler {
            id: roundHover
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: round.clicked()
        }
    }

    component Tile: Rectangle {
        id: tile
        property string glyph: ""
        property string title: ""
        property string detail: ""
        property bool on: false
        // Shows an arrow that opens a detail page; the rest of the tile still toggles.
        property bool expandable: false
        signal clicked()
        signal expanded()

        Layout.fillWidth: true
        implicitHeight: 64
        radius: 18
        color: on ? Theme.accent : tileHover.hovered ? "#24ffffff" : "#12ffffff"

        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: tile.expandable ? 44 : 12 }
            spacing: 12

            Text {
                text: tile.glyph
                color: tile.on ? Theme.onAccent : Theme.text
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 20
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: tile.title
                    color: tile.on ? Theme.onAccent : Theme.text
                    elide: Text.ElideRight
                    font.family: "Inter"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    text: tile.detail
                    color: tile.on ? Theme.onAccent : Theme.textMuted
                    opacity: tile.on ? 0.8 : 1
                    elide: Text.ElideRight
                    font.family: "Inter"
                    font.pixelSize: 11
                }
            }
        }

        HoverHandler {
            id: tileHover
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }

        Rectangle {
            visible: tile.expandable
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 6 }
            width: 32
            radius: 12
            color: arrowArea.containsMouse ? (tile.on ? "#26000000" : "#24ffffff") : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\u{f0142}"
                color: tile.on ? Theme.onAccent : Theme.textMuted
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 18
            }

            MouseArea {
                id: arrowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.expanded()
            }
        }
    }

    component PageHeader: RowLayout {
        id: header
        property string title: ""
        property bool on: false
        property bool showSwitch: true
        signal toggled()
        signal back()

        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 8

        RoundButton {
            glyph: "\u{f0141}"
            onClicked: header.back()
        }

        Text {
            Layout.fillWidth: true
            text: header.title
            color: Theme.text
            font.family: "Inter"
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }

        // On/off switch.
        Rectangle {
            visible: header.showSwitch
            implicitWidth: 46
            implicitHeight: 26
            radius: 13
            color: header.on ? Theme.accent : "#2effffff"

            Rectangle {
                width: 20
                height: 20
                radius: 10
                y: 3
                x: header.on ? parent.width - width - 3 : 3
                color: header.on ? Theme.onAccent : Theme.textMuted
                Behavior on x { NumberAnimation { duration: 120 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: header.toggled()
            }
        }
    }

    component ListRow: Rectangle {
        id: row
        property string glyph: ""
        property string label: ""
        property string tag: ""
        property string trailing: ""
        property bool highlighted: false
        // False for read-only rows (the connected monitors).
        property bool interactive: true
        signal clicked()

        implicitHeight: tag !== "" ? 52 : 44
        radius: 14
        color: row.interactive && rowArea.containsMouse ? "#18ffffff" : "transparent"

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12

            Text {
                Layout.preferredWidth: 22
                horizontalAlignment: Text.AlignHCenter
                text: row.glyph
                color: row.highlighted ? Theme.accent : Theme.text
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 18
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.label
                    color: row.highlighted ? Theme.accent : Theme.text
                    elide: Text.ElideRight
                    font.family: "Inter"
                    font.pixelSize: 13
                    font.weight: row.highlighted ? Font.DemiBold : Font.Medium
                }

                Text {
                    Layout.fillWidth: true
                    visible: row.tag !== ""
                    text: row.tag
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    font.family: "Inter"
                    font.pixelSize: 11
                }
            }

            Text {
                visible: row.trailing !== ""
                text: row.trailing
                color: Theme.textDim
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 14
            }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            enabled: row.interactive
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }
    }

    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        leftPadding: 12
        color: Theme.textDim
        font.family: "Inter"
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    component SliderRow: RowLayout {
        id: slider
        property string glyph: ""
        property real value: 0
        property real minimum: 0
        property bool muted: false
        signal moved(real v)
        signal glyphClicked()

        spacing: 12

        Text {
            Layout.preferredWidth: 24
            horizontalAlignment: Text.AlignHCenter
            text: slider.glyph
            color: slider.muted ? Theme.textDim : Theme.text
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 20

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: slider.glyphClicked()
            }
        }

        Item {
            id: track
            Layout.fillWidth: true
            implicitHeight: 28

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 28
                radius: 14
                color: "#18ffffff"

                Rectangle {
                    height: parent.height
                    radius: 14
                    width: Math.max(height, parent.width * Math.max(0, Math.min(1, slider.value)))
                    color: slider.muted ? Theme.textDisabled : Theme.accent
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function apply(x) {
                    slider.moved(Math.max(slider.minimum, Math.min(1, x / width)));
                }
                onPressed: mouse => apply(mouse.x)
                onPositionChanged: mouse => { if (pressed) apply(mouse.x); }
                onWheel: wheel => {
                    const step = wheel.angleDelta.y > 0 || wheel.angleDelta.x < 0 ? 0.05 : -0.05;
                    slider.moved(Math.max(slider.minimum, Math.min(1, slider.value + step)));
                }
            }
        }

        Text {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: Math.round(slider.value * 100) + "%"
            color: Theme.textMuted
            font.family: "Inter"
            font.pixelSize: 12
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }
}
