import QtQuick
import Quickshell

// Hover label for a bar item. It hangs just under the bar, never takes focus
// and is never an interaction target, so the pointer leaving the item is all
// that is needed to dismiss it — unlike the click-through popups, which the
// tray menus and the calendar still use because those are things to act on.
Scope {
    id: root

    required property var anchorItem
    required property var barWindow
    property string title: ""
    property string body: ""
    property bool active: false

    // Transparent strip between the bar and the bubble. It is part of the
    // popup window rather than an anchor offset so the gap cannot land the
    // window under the pointer and fight the hover state that opened it.
    readonly property int gap: 6

    onActiveChanged: {
        if (active && (title !== "" || body !== "")) {
            delay.restart();
        } else {
            delay.stop();
            popup.visible = false;
        }
    }

    Timer {
        id: delay
        interval: 320
        onTriggered: popup.visible = true
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        implicitWidth: bubble.implicitWidth
        implicitHeight: bubble.implicitHeight + root.gap

        anchor {
            window: root.barWindow
            item: root.anchorItem
            edges: Edges.Bottom
            gravity: Edges.Bottom
            adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipY
        }

        Rectangle {
            id: bubble

            y: root.gap
            width: parent.width
            height: parent.height - root.gap
            implicitWidth: column.implicitWidth + 22
            implicitHeight: column.implicitHeight + 16
            radius: 10
            color: "#f20d0e12"
            border.width: 1
            border.color: "#24ffffff"

            Column {
                id: column

                anchors.centerIn: parent
                spacing: 3

                Text {
                    visible: root.title !== ""
                    text: root.title
                    color: "#7f8493"
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    visible: root.body !== ""
                    text: root.body
                    color: "#e8eaf0"
                    font.family: "Inter"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    lineHeight: 1.25
                }
            }
        }
    }
}
