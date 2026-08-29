import QtQuick
import QtQuick.Layouts

// One selectable endpoint in AudioMenu. Kept as its own file because both the
// output and the input Repeater instantiate it and QML delegates cannot be
// shared inline.
Item {
    id: root

    required property var node
    required property bool isOutput
    required property var menu

    readonly property bool current: menu.isDefault(node, isOutput)

    height: 34

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: rowHover.hovered ? "#18ffffff" : "transparent"

        Behavior on color {
            ColorAnimation { duration: 100 }
        }
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 10
        }
        spacing: 9

        Text {
            Layout.preferredWidth: 18
            horizontalAlignment: Text.AlignHCenter
            text: root.menu.deviceIcon(root.node, root.isOutput)
            color: root.current ? "#8fb7e8" : "#aeb4c3"
            font.family: "FiraCode Nerd Font Mono"
            font.pixelSize: 16
        }

        Text {
            Layout.fillWidth: true
            text: root.menu.deviceLabel(root.node)
            color: root.current ? "#e8eaf0" : "#aeb4c3"
            elide: Text.ElideRight
            font.family: "Inter"
            font.pixelSize: 14
            font.weight: root.current ? Font.DemiBold : Font.Medium
        }

        // The internal/external answer in one word -- the icon alone cannot
        // separate a built-in speaker from a USB one.
        Text {
            text: root.menu.deviceKind(root.node)
            color: "#656a78"
            font.family: "Inter"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Text {
            Layout.preferredWidth: 14
            horizontalAlignment: Text.AlignHCenter
            text: root.current ? "󰄬" : ""
            color: "#8fb7e8"
            font.family: "FiraCode Nerd Font Mono"
            font.pixelSize: 14
        }
    }

    HoverHandler {
        id: rowHover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.menu.selectDevice(root.node, root.isOutput)
    }
}
