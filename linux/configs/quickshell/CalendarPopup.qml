import QtQuick
import Quickshell

// The clock's dropdown: today's date large at the top, then the month grid.
// Month title left, round ‹ › on the right, and a "Today" pill that appears
// only once you have paged away from the current month.
Scope {
    id: root

    required property var anchorItem
    required property var barWindow
    property date today: new Date()
    property int shownMonth: today.getMonth()
    property int shownYear: today.getFullYear()
    readonly property bool onCurrentMonth: shownMonth === today.getMonth()
        && shownYear === today.getFullYear()

    readonly property int cellSize: 38
    readonly property int cellGap: 4

    function open() {
        today = new Date();
        showToday();
        popup.visible = true;
    }

    function showToday() {
        shownMonth = today.getMonth();
        shownYear = today.getFullYear();
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

    component NavButton: Rectangle {
        id: button
        property string label: ""
        signal tapped()

        width: 32
        height: 32
        radius: 16
        color: hover.hovered ? "#1fffffff" : "#0dffffff"

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Text {
            anchors.centerIn: parent
            // Optical centring: the guillemets sit low and wide in Inter.
            anchors.verticalCenterOffset: -1
            text: button.label
            color: Theme.text
            font.family: "Inter"
            font.pixelSize: 20
            font.weight: Font.Medium
        }

        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: button.tapped()
        }
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        grabFocus: true
        implicitWidth: card.implicitWidth
        implicitHeight: card.implicitHeight

        anchor {
            window: root.barWindow
            item: root.anchorItem
            edges: Edges.Top
            gravity: Edges.Top
            adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipY
        }

        Rectangle {
            id: card
            anchors.fill: parent
            implicitWidth: content.implicitWidth + 36
            implicitHeight: content.implicitHeight + 36
            color: Theme.menu
            border.width: 1
            border.color: "#1fffffff"
            radius: 18

            Column {
                id: content
                anchors {
                    top: parent.top
                    left: parent.left
                    margins: 18
                }
                spacing: 14

                // Today, large.
                Column {
                    spacing: 2

                    Text {
                        text: Qt.formatDate(root.today, "dddd")
                        color: Theme.accent
                        font.family: "Inter"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: Qt.formatDate(root.today, "d MMMM yyyy")
                        color: Theme.text
                        font.family: "Inter"
                        font.pixelSize: 24
                        font.weight: Font.Bold
                    }
                }

                Rectangle {
                    width: grid.width
                    height: 1
                    color: "#14ffffff"
                }

                // Month title and navigation.
                Item {
                    width: grid.width
                    height: 32

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 4
                            verticalCenter: parent.verticalCenter
                        }
                        text: Qt.formatDate(new Date(root.shownYear, root.shownMonth, 1), "MMMM yyyy")
                        color: Theme.text
                        font.family: "Inter"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    Row {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        Rectangle {
                            visible: !root.onCurrentMonth
                            width: todayLabel.implicitWidth + 24
                            height: 32
                            radius: 16
                            color: todayHover.hovered ? "#1fffffff" : "#0dffffff"

                            Text {
                                id: todayLabel
                                anchors.centerIn: parent
                                text: "Today"
                                color: Theme.accent
                                font.family: "Inter"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            HoverHandler {
                                id: todayHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: root.showToday()
                            }
                        }

                        NavButton {
                            label: "‹"
                            onTapped: root.moveMonth(-1)
                        }

                        NavButton {
                            label: "›"
                            onTapped: root.moveMonth(1)
                        }
                    }
                }

                Grid {
                    id: grid
                    columns: 7
                    rowSpacing: root.cellGap
                    columnSpacing: root.cellGap

                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]

                        delegate: Text {
                            required property string modelData
                            required property int index
                            width: root.cellSize
                            height: 22
                            text: modelData
                            color: index >= 5 ? Theme.textDisabled : Theme.textDim
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }

                    Repeater {
                        model: 42

                        delegate: Rectangle {
                            id: cell
                            required property int index
                            property date cellDate: root.cellDate(index)
                            property bool currentMonth: cellDate.getMonth() === root.shownMonth
                                && cellDate.getFullYear() === root.shownYear
                            property bool todayCell: root.isToday(cellDate)
                            property bool weekend: index % 7 >= 5

                            width: root.cellSize
                            height: root.cellSize
                            radius: width / 2
                            color: todayCell ? Theme.accent
                                : cellHover.hovered && currentMonth ? "#14ffffff" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: cell.cellDate.getDate()
                                color: cell.todayCell ? Theme.onAccent
                                    : !cell.currentMonth ? Theme.textDisabled
                                    : cell.weekend ? Theme.textMuted : Theme.text
                                font.family: "Inter"
                                font.pixelSize: 14
                                font.weight: cell.todayCell ? Font.Bold : Font.Medium
                                font.features: { "tnum": 1 }
                            }

                            HoverHandler {
                                id: cellHover
                            }
                        }
                    }
                }
            }
        }
    }
}
