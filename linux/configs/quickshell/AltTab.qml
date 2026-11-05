import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Window switcher (Alt+Tab): the open windows in most-recently-used order as
// a row of still previews. Each Alt+Tab press selects the next window along
// (Alt+Shift+Tab the one back) and the focus follows 150 ms after the last
// press; the row stays up for 0.6 s after the last press. hyprland.lua's binds drive shell.qml's altTab; this
// file only draws, so it takes no keyboard focus. Clicking a card focuses it
// and closes the row, a click on the backdrop just closes it. shell.qml
// creates it through a LazyLoader only while open; the previews are single
// frames.
PanelWindow {
    id: switcher

    required property var shell

    readonly property real thumbWidth: 236
    readonly property real thumbHeight: 148

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "quickshell-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: switcher.shell.altTabCancel()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(switcher.width - 80, row.implicitWidth + 32)
        height: row.implicitHeight + 32
        radius: 22
        color: Theme.menu
        border.width: 1
        border.color: "#24ffffff"
        clip: true

        Flow {
            id: row
            x: 16
            y: 16
            width: Math.min(switcher.width - 112, switcher.shell.switcherWindows.length * (switcher.thumbWidth + spacing))
            spacing: 12

            Repeater {
                model: switcher.shell.switcherWindows

                delegate: Rectangle {
                    id: entry

                    required property var modelData
                    required property int index
                    readonly property bool selected: index === switcher.shell.switcherIndex

                    width: switcher.thumbWidth
                    height: switcher.thumbHeight + 44
                    radius: 14
                    color: selected ? "#22ffffff" : (entryHover.hovered ? "#12ffffff" : "transparent")
                    border.width: selected ? 2 : 0
                    border.color: Theme.accent

                    Rectangle {
                        id: frame
                        x: 8
                        y: 8
                        width: switcher.thumbWidth - 16
                        height: switcher.thumbHeight - 16
                        radius: 8
                        color: "#1affffff"
                        clip: true

                        ScreencopyView {
                            anchors.fill: parent
                            anchors.margins: 1
                            captureSource: entry.modelData.wayland
                            live: false
                        }
                    }

                    Column {
                        anchors.top: frame.bottom
                        anchors.topMargin: 6
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 1

                        Text {
                            width: parent.width
                            text: (entry.modelData.lastIpcObject || {}).title || ""
                            color: "#e8eaf0"
                            font.family: "Inter"
                            font.pixelSize: 13
                            font.weight: entry.selected ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: (entry.modelData.lastIpcObject || {}).class || ""
                            color: Theme.textMuted
                            font.family: "Inter"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    HoverHandler {
                        id: entryHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            switcher.shell.switcherIndex = entry.index;
                            switcher.shell.altTabCommit();
                        }
                    }
                }
            }
        }
    }
}
