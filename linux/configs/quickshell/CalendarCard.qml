import QtQuick
import QtQuick.Layouts
import "bar-logic.mjs" as BarLogic

// Month calendar for the desktop: Material 3 date-picker look, today in a
// filled primary circle, weekends and neighbouring-month days dimmed. The
// arrows browse; the card snaps back to this month whenever the date rolls.
DesktopCard {
    id: card

    required property date today
    property color primary: "#a8c7fa"
    property int shownYear: today.getFullYear()
    property int shownMonth: today.getMonth()
    readonly property bool onThisMonth: shownYear === today.getFullYear()
        && shownMonth === today.getMonth()

    function moveMonth(offset) {
        const date = new Date(shownYear, shownMonth + offset, 1);
        shownYear = date.getFullYear();
        shownMonth = date.getMonth();
    }

    function resetMonth() {
        shownYear = today.getFullYear();
        shownMonth = today.getMonth();
    }

    // `today` ticks every minute; only a new day should undo browsing.
    readonly property string dayKey: today.toDateString()
    onDayKeyChanged: resetMonth()
    implicitHeight: body.implicitHeight + padding * 2

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6

            Text {
                text: Qt.formatDate(new Date(card.shownYear, card.shownMonth, 1), "MMMM yyyy")
                color: "#e8eaf0"
                font.family: "Inter Display"
                font.pixelSize: 18
                font.weight: Font.DemiBold

                // Clicking the title jumps back to today's month.
                MouseArea {
                    anchors.fill: parent
                    enabled: !card.onThisMonth
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: card.resetMonth()
                }
            }

            Item { Layout.fillWidth: true }

            NavButton { glyph: "\u{f0141}"; onClicked: card.moveMonth(-1) }
            NavButton { glyph: "\u{f0142}"; onClicked: card.moveMonth(1) }
        }

        Grid {
            id: grid
            Layout.fillWidth: true
            columns: 7
            rowSpacing: 2
            readonly property real cell: width / 7

            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]

                delegate: Text {
                    required property string modelData
                    required property int index
                    width: grid.cell
                    height: 28
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: index >= 5 ? "#6f7584" : "#9aa0ae"
                    font.family: "Inter"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            Repeater {
                model: BarLogic.monthGrid(card.shownYear, card.shownMonth)

                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property bool isToday: modelData.year === card.today.getFullYear()
                        && modelData.month === card.today.getMonth()
                        && modelData.day === card.today.getDate()

                    width: grid.cell
                    height: 38

                    Rectangle {
                        anchors.centerIn: parent
                        width: 36
                        height: 36
                        radius: 18
                        color: parent.isToday ? card.primary : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.day
                        opacity: parent.modelData.inMonth ? 1 : 0.3
                        color: parent.isToday ? "#062e6f"
                            : parent.index % 7 >= 5 ? "#9aa0ae" : "#e8eaf0"
                        font.family: "Inter"
                        font.pixelSize: 14
                        font.weight: parent.isToday ? Font.Bold : Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }

    component NavButton: Rectangle {
        id: button

        property string glyph: ""
        signal clicked()

        implicitWidth: 34
        implicitHeight: 34
        radius: 17
        color: mouse.containsMouse ? "#1fffffff" : "transparent"

        Behavior on color {
            ColorAnimation { duration: 140 }
        }

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: "#c4c8d4"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 20
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
