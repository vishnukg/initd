import QtQuick

Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property color foreground: "#e8eaf0"
    property color background: "transparent"
    property bool clickable: false
    property bool secondaryClickable: false
    property int horizontalPadding: 9
    property int iconSize: 21
    property var barWindow: null
    property string tooltipTitle: ""
    property string tooltipBody: ""
    signal clicked()
    signal secondaryClicked()

    implicitWidth: content.implicitWidth + horizontalPadding * 2
    implicitHeight: 31
    radius: 8
    color: hover.hovered ? "#18ffffff" : background

    Behavior on color {
        ColorAnimation { duration: 140 }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: root.icon !== "" ? 6 : 0

        Text {
            visible: root.icon !== ""
            width: visible ? root.iconSize : 0
            height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.icon
            color: root.foreground
            font.family: "FiraCode Nerd Font"
            font.pixelSize: root.iconSize
            font.weight: Font.Medium
        }

        Text {
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.foreground
            font.family: "Berkeley Mono"
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }
    }

    HoverHandler {
        id: hover
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    // Reading an item is hover-only; clicking is reserved for items that
    // actually do something (cycle the power profile, mute, open a menu).
    TapHandler {
        enabled: root.clickable
        acceptedButtons: Qt.LeftButton
        onTapped: root.clicked()
    }

    // Right-click is the escape hatch for an item whose left-click had to be
    // handed over to a dropdown: audio keeps one-click mute here.
    TapHandler {
        enabled: root.secondaryClickable
        acceptedButtons: Qt.RightButton
        onTapped: root.secondaryClicked()
    }

    BarTooltip {
        anchorItem: root
        barWindow: root.barWindow
        title: root.tooltipTitle
        body: root.tooltipBody
        active: hover.hovered
    }

}
