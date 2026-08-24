import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property color foreground: "#e8eaf0"
    property color background: "transparent"
    property bool clickable: false
    property int horizontalPadding: 9
    property int iconSize: 21
    property var barWindow: null
    property string detailsTitle: ""
    property string detailsBody: ""
    property string detailsAction: ""
    signal clicked()
    signal detailAction()

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
            font.family: "FiraCode Nerd Font Mono"
            font.pixelSize: root.iconSize
            font.weight: Font.Medium
        }

        Text {
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.foreground
            font.family: "Inter"
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }
    }

    HoverHandler {
        id: hover
        cursorShape: root.clickable || root.detailsTitle !== ""
            ? Qt.PointingHandCursor
            : Qt.ArrowCursor
    }

    TapHandler {
        enabled: root.clickable || root.detailsTitle !== ""
        acceptedButtons: Qt.LeftButton
        onTapped: {
            if (root.detailsTitle !== "")
                details.open();
            else
                root.clicked();
        }
    }

    DetailPopup {
        id: details
        anchorItem: root
        barWindow: root.barWindow
        title: root.detailsTitle
        body: root.detailsBody
        actionLabel: root.detailsAction
        onActionTriggered: root.detailAction()
    }

}
