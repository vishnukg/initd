import QtQuick
import QtQuick.Layouts

// One row in a bar dropdown: icon · label · dim tag · checkmark. Shared by
// AudioMenu and DisplayMenu, which want identical chrome over different data.
// Rows that are a readout rather than a choice set `interactive: false`, which
// drops the hover highlight and the pointer cursor with it.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property string tag: ""
    property bool checked: false
    property bool interactive: true
    signal activated()

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
            text: root.icon
            color: root.checked ? "#8fb7e8" : "#aeb4c3"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 16
        }

        Text {
            Layout.fillWidth: true
            text: root.label
            color: root.checked ? "#e8eaf0" : "#aeb4c3"
            elide: Text.ElideRight
            font.family: "Inter"
            font.pixelSize: 14
            font.weight: root.checked ? Font.DemiBold : Font.Medium
        }

        Text {
            visible: root.tag !== ""
            text: root.tag
            color: "#656a78"
            font.family: "Inter"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Text {
            Layout.preferredWidth: 14
            horizontalAlignment: Text.AlignHCenter
            text: root.checked ? "󰄬" : ""
            color: "#8fb7e8"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 14
        }
    }

    HoverHandler {
        id: rowHover
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.interactive
        onTapped: root.activated()
    }
}
