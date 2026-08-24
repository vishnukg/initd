import QtQuick
import Quickshell

Scope {
    id: root

    required property var anchorItem
    required property var barWindow
    property string title: ""
    property string body: ""
    property string actionLabel: ""
    signal actionTriggered()

    function open() {
        popup.visible = true;
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        grabFocus: true
        implicitWidth: 280
        implicitHeight: content.implicitHeight + 28

        anchor {
            window: root.barWindow
            item: root.anchorItem
            edges: Edges.Top
            gravity: Edges.Top
            adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipY
        }

        Rectangle {
            anchors.fill: parent
            color: "#f20d0e12"
            border.width: 1
            border.color: "#24ffffff"
            radius: 12

            Column {
                id: content

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 14
                }
                spacing: 8

                Text {
                    width: parent.width
                    text: root.title
                    color: "#e8eaf0"
                    font.family: "Inter"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: root.body
                    color: "#aeb4c3"
                    wrapMode: Text.Wrap
                    font.family: "Inter"
                    font.pixelSize: 14
                    lineHeight: 1.25
                }

                Rectangle {
                    visible: root.actionLabel !== ""
                    width: parent.width
                    height: visible ? 34 : 0
                    radius: 8
                    color: actionHover.hovered ? "#a68fb7e8" : "#8f8fb7e8"

                    Text {
                        anchors.centerIn: parent
                        text: root.actionLabel
                        color: "#0b0c10"
                        font.family: "Inter"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }

                    HoverHandler {
                        id: actionHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: {
                            root.actionTriggered();
                            popup.visible = false;
                        }
                    }
                }
            }
        }
    }
}
