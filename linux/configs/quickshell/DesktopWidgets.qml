import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Wayland
import "bar-logic.mjs" as BarLogic

// Desktop widgets in the Material 3 / ChromeOS-Googlebook idiom: a large
// two-tone clock with an "At a Glance" line, then tonal cards for system
// load, the month, headlines and media. They live on the Bottom layer -- above the
// wallpaper, below every window -- so they are only seen on an empty
// workspace, and they read everything from the bar's own state (`shell`), so
// nothing here polls.
//
// Each widget is its own small layer surface (WidgetWindow.qml) at a saved
// spot. Arranging them is a separate mode (DesktopEditor.qml): right-click a
// widget or press $mod+SHIFT+d, drag, then Esc or Done.
Scope {
    id: desk

    required property var shell
    required property var screen
    readonly property color primary: "#a8c7fa"
    readonly property color onSurface: "#e8eaf0"
    readonly property color muted: "#9aa0ae"

    // Default layout, the one arranged by hand on the laptop (2026-11-02) and
    // expressed as rules rather than pixels so any screen size gets the same
    // composition: a card column 64px in from the right edge, the clock
    // centred over it (so it stays centred as the weather text changes its
    // width), 34px under the clock and 16px between cards. Saved spots in
    // the state file still win on a machine where something was dragged.
    readonly property int cardWidth: 440
    readonly property int edge: 64
    readonly property int top: 96
    readonly property int clockGap: 34
    readonly property int gap: 16
    readonly property real columnX: (screen ? screen.width : 0) - edge - cardWidth

    // Saved spots, keyed "<monitor>:<widget>" so each monitor keeps its own
    // arrangement. Machine-local state, not config: it lives under
    // ~/.local/state/quickshell, never in the repo.
    property var placements: ({})
    // Live positions while the editor drags a widget: { <widget>: { x, y } }.
    property var dragging: ({})

    function dragTo(key, x, y) {
        const next = Object.assign({}, dragging);
        if (x === null)
            delete next[key];
        else
            next[key] = { x: x, y: y };
        dragging = next;
    }

    function placementKey(key) {
        return (screen ? screen.name : "") + ":" + key;
    }

    function savePlacement(key, x, y) {
        const next = Object.assign({}, placements);
        next[placementKey(key)] = { x: Math.round(x / 8) * 8, y: Math.round(y / 8) * 8 };
        placements = next;
        placementFile.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function resetPlacements() {
        const next = Object.assign({}, placements);
        for (const key of Object.keys(next))
            if (key.startsWith((screen ? screen.name : "") + ":"))
                delete next[key];
        placements = next;
        placementFile.setText(JSON.stringify(next, null, 2) + "\n");
    }

    // The playing player wins; otherwise the first one that has a track.
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

    // `qs ipc call bar resetDesktop` puts every widget back in the stack.
    Connections {
        target: desk.shell
        function onResetDesktop() {
            desk.resetPlacements();
        }
    }

    FileView {
        id: placementFile
        path: Quickshell.statePath("desktop-widgets.json")
        // A missing file just means nothing has been moved yet; parse
        // failures fall back to the default layout (parsePlacements).
        onLoaded: desk.placements = BarLogic.parsePlacements(text())
    }

    // Only while arranging: the overlay is screen-sized, the widgets are not.
    LazyLoader {
        active: desk.shell.desktopEditing && desk.shell.desktopVisible

        DesktopEditor {
            host: desk
            widgets: [clockWidget, systemWidget, calendarWidget, newsWidget, mediaWidget]
        }
    }

    // --- Clock and At a Glance -----------------------------------------------
    WidgetWindow {
        id: clockWidget
        key: "clock"
        title: "Clock"
        desk: desk
        visible: desk.shell.desktopVisible
        defaultX: desk.columnX + (desk.cardWidth - implicitWidth) / 2
        defaultY: desk.top

        ColumnLayout {
            spacing: 2
            width: implicitWidth

            Text {
                Layout.alignment: Qt.AlignRight
                text: BarLogic.greeting(desk.shell.clockDate.getHours())
                color: desk.muted
                font.family: "Inter Display"
                font.pixelSize: 20
                font.weight: Font.Medium
            }

            Row {
                Layout.alignment: Qt.AlignRight
                spacing: 0

                Text {
                    text: Qt.formatDateTime(desk.shell.clockDate, "HH")
                    color: "#d3e3fd"
                    font.family: "Inter Display"
                    font.pixelSize: 132
                    font.weight: Font.DemiBold
                    font.letterSpacing: -4
                    font.features: { "tnum": 1 }
                }

                Text {
                    text: ":"
                    color: desk.muted
                    font.family: "Inter Display"
                    font.pixelSize: 132
                    font.weight: Font.Light
                }

                Text {
                    text: Qt.formatDateTime(desk.shell.clockDate, "mm")
                    color: desk.primary
                    font.family: "Inter Display"
                    font.pixelSize: 132
                    font.weight: Font.DemiBold
                    font.letterSpacing: -4
                    font.features: { "tnum": 1 }
                }
            }

            Text {
                Layout.alignment: Qt.AlignRight
                text: Qt.formatDateTime(desk.shell.clockDate, "dddd, MMMM d")
                color: desk.onSurface
                font.family: "Inter Display"
                font.pixelSize: 22
                font.weight: Font.Medium
            }

            // Weather chip: tonal pill, coloured by the bar's temperature ramp.
            // Its own line, and the condition elides: wttr.in names run as
            // long as "Moderate or heavy rain with thunder", and anything
            // wider than the window would push the whole column off-screen
            // (the layer surface has a fixed width and clips).
            Rectangle {
                Layout.alignment: Qt.AlignRight
                Layout.topMargin: 10
                visible: desk.shell.weatherTemp !== "--"
                radius: height / 2
                color: "#2effffff"
                implicitHeight: 34
                implicitWidth: chip.implicitWidth + 26

                Row {
                    id: chip
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: desk.shell.weatherIcon()
                        color: desk.shell.weatherColor()
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        width: Math.min(implicitWidth, desk.cardWidth - 80)
                        elide: Text.ElideRight
                        text: desk.shell.weatherTemp.replace("+", "")
                            + "  ·  " + desk.shell.weatherCondition
                        color: desk.onSurface
                        font.family: "Inter"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // --- System --------------------------------------------------------------
    WidgetWindow {
        id: systemWidget
        key: "system"
        title: "System"
        desk: desk
        visible: desk.shell.desktopVisible
        defaultX: desk.columnX
        defaultY: clockWidget.defaultY + clockWidget.implicitHeight + desk.clockGap

        DesktopCard {
            width: desk.cardWidth
            implicitHeight: rings.implicitHeight + padding * 2

            RowLayout {
                id: rings
                anchors.left: parent.left
                anchors.right: parent.right

                RingGauge {
                    Layout.alignment: Qt.AlignHCenter
                    value: BarLogic.fraction(desk.shell.cpuText)
                    icon: "\u{f035b}"
                    label: "CPU"
                    reading: desk.shell.cpuText
                    accent: "#a8c7fa"
                }

                RingGauge {
                    Layout.alignment: Qt.AlignHCenter
                    value: BarLogic.fraction(desk.shell.memoryPercent)
                    icon: "\u{f061a}"
                    label: "Memory"
                    reading: desk.shell.memoryText
                    accent: "#c4b5fd"
                }

                RingGauge {
                    Layout.alignment: Qt.AlignHCenter
                    value: 1 - BarLogic.fraction(desk.shell.diskPercent)
                    icon: "\u{f02ca}"
                    label: "Disk free"
                    reading: desk.shell.diskText
                    accent: "#7dd3c7"
                }

                RingGauge {
                    Layout.alignment: Qt.AlignHCenter
                    visible: UPower.displayDevice.isLaptopBattery
                    value: UPower.displayDevice.percentage
                    icon: desk.shell.batteryIcon()
                    label: desk.shell.batteryPlugged() ? "Charging" : "Battery"
                    reading: desk.shell.batteryPercentage() + "%"
                    accent: desk.shell.batteryPercentage() <= 15 && !desk.shell.batteryPlugged()
                        ? "#f2b8b5" : "#8fd6b8"
                }
            }
        }
    }

    // --- Calendar ------------------------------------------------------------
    WidgetWindow {
        id: calendarWidget
        key: "calendar"
        title: "Calendar"
        desk: desk
        visible: desk.shell.desktopVisible
        defaultX: desk.columnX
        defaultY: systemWidget.defaultY + systemWidget.implicitHeight + desk.gap

        CalendarCard {
            width: desk.cardWidth
            today: desk.shell.clockDate
        }
    }

    // --- Headlines ---------------------------------------------------------
    // Middle-left by default: the left side to itself, vertically centred.
    WidgetWindow {
        id: newsWidget
        key: "news"
        title: "Headlines"
        desk: desk
        visible: desk.shell.desktopVisible
        defaultX: desk.edge
        defaultY: ((desk.screen ? desk.screen.height : 0) - implicitHeight) / 2

        NewsCard {
            width: desk.cardWidth
            news: desk.shell.news
            now: desk.shell.clockDate
        }
    }

    // --- Now playing ---------------------------------------------------------
    WidgetWindow {
        id: mediaWidget
        key: "media"
        title: "Now playing"
        desk: desk
        // Hidden when no player has a track; last in the default stack so
        // it appearing never shifts the others.
        visible: desk.shell.desktopVisible && desk.player !== null
        defaultX: desk.columnX
        defaultY: calendarWidget.defaultY + calendarWidget.implicitHeight + desk.gap

        DesktopCard {
            width: desk.cardWidth
            implicitHeight: 148

            RowLayout {
                anchors.fill: parent
                spacing: 18

                Rectangle {
                    Layout.preferredWidth: 108
                    Layout.preferredHeight: 108
                    radius: 20
                    color: "#26a8c7fa"
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: "\u{f075a}"
                        color: desk.primary
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 44
                    }

                    Image {
                        id: art
                        anchors.fill: parent
                        source: desk.player ? desk.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 216
                        sourceSize.height: 216
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: desk.player ? (desk.player.trackTitle || "Unknown title") : ""
                        color: desk.onSurface
                        elide: Text.ElideRight
                        font.family: "Inter Display"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: desk.player ? (desk.player.trackArtist || desk.player.identity) : ""
                        color: desk.muted
                        elide: Text.ElideRight
                        font.family: "Inter"
                        font.pixelSize: 14
                    }

                    // Progress; Mpris only pushes position on seeks, so a
                    // timer nudges it while playing.
                    Rectangle {
                        id: track
                        visible: desk.player && desk.player.positionSupported && desk.player.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        implicitHeight: 4
                        radius: 2
                        color: "#33a8c7fa"

                        Rectangle {
                            height: parent.height
                            radius: 2
                            color: desk.primary
                            width: desk.player && desk.player.length > 0
                                ? parent.width * Math.min(1, desk.player.position / desk.player.length)
                                : 0
                        }

                        Timer {
                            running: desk.player && desk.player.isPlaying && track.visible
                            interval: 1000
                            repeat: true
                            onTriggered: desk.player.positionChanged()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 6

                        Text {
                            visible: track.visible
                            text: desk.player
                                ? BarLogic.trackTime(desk.player.position)
                                    + " / " + BarLogic.trackTime(desk.player.length)
                                : ""
                            color: desk.muted
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.features: { "tnum": 1 }
                        }

                        Item { Layout.fillWidth: true }

                        MediaButton {
                            glyph: "\u{f04ae}"
                            enabled: desk.player && desk.player.canGoPrevious
                            onClicked: desk.player.previous()
                        }

                        MediaButton {
                            glyph: desk.player && desk.player.isPlaying ? "\u{f03e4}" : "\u{f040a}"
                            filled: true
                            enabled: desk.player && desk.player.canTogglePlaying
                            onClicked: desk.player.togglePlaying()
                        }

                        MediaButton {
                            glyph: "\u{f04ad}"
                            enabled: desk.player && desk.player.canGoNext
                            onClicked: desk.player.next()
                        }
                    }
                }
            }
        }
    }

    component MediaButton: Rectangle {
        id: button

        property string glyph: ""
        property bool filled: false
        signal clicked()

        implicitWidth: filled ? 52 : 40
        implicitHeight: 40
        radius: filled ? 16 : 20
        opacity: enabled ? 1 : 0.35
        color: filled
            ? (mouse.containsMouse ? "#bdd4fb" : desk.primary)
            : (mouse.containsMouse ? "#1fffffff" : "transparent")

        Behavior on color {
            ColorAnimation { duration: 140 }
        }

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: button.filled ? "#062e6f" : desk.onSurface
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 22
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: button.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
