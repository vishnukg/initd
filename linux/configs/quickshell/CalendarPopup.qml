import QtQuick
import Quickshell

Scope {
    id: root

    required property var anchorItem
    required property var barWindow
    property date today: new Date()
    property int shownMonth: today.getMonth()
    property int shownYear: today.getFullYear()

    function open() {
        today = new Date();
        shownMonth = today.getMonth();
        shownYear = today.getFullYear();
        popup.visible = true;
    }

    function moveMonth(offset) {
        const date = new Date(shownYear, shownMonth + offset, 1);
        shownMonth = date.getMonth();
        shownYear = date.getFullYear();
    }

    function cellDate(index) {
        const firstDay = new Date(shownYear, shownMonth, 1).getDay();
        const mondayOffset = firstDay === 0 ? 6 : firstDay - 1;
        return new Date(shownYear, shownMonth, index - mondayOffset + 1);
    }

    function isToday(date) {
        return date.getFullYear() === today.getFullYear()
            && date.getMonth() === today.getMonth()
            && date.getDate() === today.getDate();
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        grabFocus: true
        implicitWidth: 330
        implicitHeight: 350

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
            radius: 14

            Column {
                anchors {
                    fill: parent
                    margins: 14
                }
                spacing: 10

                Item {
                    width: parent.width
                    height: 34

                    Rectangle {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        width: 34
                        height: 34
                        radius: 8
                        color: previousHover.hovered ? "#18ffffff" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "‹"
                            color: "#aeb4c3"
                            font.family: "Berkeley Mono"
                            font.pixelSize: 24
                        }

                        HoverHandler {
                            id: previousHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: root.moveMonth(-1)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Qt.formatDate(new Date(root.shownYear, root.shownMonth, 1), "MMMM yyyy")
                        color: "#e8eaf0"
                        font.family: "Berkeley Mono"
                        font.pixelSize: 17
                        font.weight: Font.Bold
                    }

                    Rectangle {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        width: 34
                        height: 34
                        radius: 8
                        color: nextHover.hovered ? "#18ffffff" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "›"
                            color: "#aeb4c3"
                            font.family: "Berkeley Mono"
                            font.pixelSize: 24
                        }

                        HoverHandler {
                            id: nextHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: root.moveMonth(1)
                        }
                    }
                }

                Grid {
                    width: parent.width
                    columns: 7
                    rowSpacing: 5
                    columnSpacing: 5

                    Repeater {
                        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

                        delegate: Text {
                            required property string modelData
                            width: 38
                            height: 24
                            text: modelData
                            color: "#656a78"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.family: "Berkeley Mono"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    Repeater {
                        model: 42

                        delegate: Rectangle {
                            required property int index
                            property date cellDate: root.cellDate(index)
                            property bool currentMonth: cellDate.getMonth() === root.shownMonth
                                && cellDate.getFullYear() === root.shownYear
                            property bool todayCell: root.isToday(cellDate)

                            width: 38
                            height: 34
                            radius: 9
                            color: todayCell ? "#8fb7e8" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: parent.cellDate.getDate()
                                color: parent.todayCell
                                    ? "#0b0c10"
                                    : parent.currentMonth ? "#e8eaf0" : "#4d515d"
                                font.family: "Berkeley Mono"
                                font.pixelSize: 14
                                font.weight: parent.todayCell ? Font.Bold : Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }
}
