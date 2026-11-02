import QtQuick
import QtQuick.Layouts
import Quickshell
import "bar-logic.mjs" as BarLogic

// Headlines, one page per region: World, then Australia, then India
// (linux/scripts/news.mjs). Swipe or scroll sideways -- two-finger swipe on
// the touchpad, the mouse wheel, or a click-drag -- or click a chip. A
// headline opens in the browser.
//
// A hand-rolled pager rather than a horizontal ListView: wheel input on a
// snapping ListView can come to rest between pages, and one gesture should
// always be exactly one page.
DesktopCard {
    id: card

    required property var news
    required property date now
    property color primary: "#a8c7fa"
    property int pageIndex: 0
    readonly property var sections: news && news.sections ? news.sections : []
    readonly property int perPage: 5

    function go(index) {
        pageIndex = Math.max(0, Math.min(sections.length - 1, index));
    }

    implicitHeight: body.implicitHeight + padding * 2

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 12

        // --- Header ---
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 10

            Text {
                text: "\u{f0395}"
                color: card.primary
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 20
            }

            Text {
                text: "Headlines"
                color: "#e8eaf0"
                font.family: "Inter Display"
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }

            Text {
                readonly property string age: BarLogic.timeAgo(card.news.updated, card.now.getTime())
                visible: age !== ""
                text: age === "now" ? "Just updated" : "Updated " + age + " ago"
                color: "#8f94a3"
                font.family: "Inter"
                font.pixelSize: 12
            }
        }

        // --- Region chips (Material segmented style) ---
        Row {
            spacing: 8

            Repeater {
                model: card.sections

                delegate: Rectangle {
                    id: chip

                    required property var modelData
                    required property int index
                    readonly property bool current: index === card.pageIndex

                    implicitHeight: 32
                    implicitWidth: chipText.implicitWidth + 28
                    radius: 16
                    color: current ? card.primary : chipHover.hovered ? "#24ffffff" : "#12ffffff"

                    Behavior on color { ColorAnimation { duration: 160 } }

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData.title
                        color: chip.current ? "#062e6f" : "#c4c8d4"
                        font.family: "Inter"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    HoverHandler {
                        id: chipHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: card.go(chip.index)
                    }
                }
            }
        }

        // --- Pages ---
        Item {
            id: viewport
            Layout.fillWidth: true
            implicitHeight: card.perPage * 66
            clip: true

            property real dragOffset: 0

            Row {
                id: pages
                x: -card.pageIndex * viewport.width + viewport.dragOffset
                height: parent.height

                Behavior on x {
                    enabled: !swipe.active
                    NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                }

                Repeater {
                    model: card.sections

                    delegate: Column {
                        id: page

                        required property var modelData
                        width: viewport.width
                        spacing: 2

                        Text {
                            visible: page.modelData.items.length === 0
                            width: parent.width
                            topPadding: 24
                            horizontalAlignment: Text.AlignHCenter
                            text: card.news.updated === "" ? "Loading headlines…" : "Couldn't load " + page.modelData.title + " news. Retrying soon."
                            color: "#8f94a3"
                            font.family: "Inter"
                            font.pixelSize: 14
                        }

                        Repeater {
                            model: page.modelData.items.slice(0, card.perPage)

                            delegate: Rectangle {
                                id: headline

                                required property var modelData
                                width: page.width
                                height: 64
                                radius: 14
                                color: rowHover.hovered ? "#14ffffff" : "transparent"

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Column {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 10
                                        rightMargin: 10
                                    }
                                    spacing: 3

                                    Text {
                                        width: parent.width
                                        text: headline.modelData.title
                                        color: "#e8eaf0"
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        lineHeight: 1.1
                                        font.family: "Inter"
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }

                                    Text {
                                        width: parent.width
                                        readonly property string age: BarLogic.timeAgo(headline.modelData.published, card.now.getTime())
                                        text: headline.modelData.source + (age ? "  ·  " + age : "")
                                            + (page.modelData.stale ? "  ·  offline" : "")
                                        color: "#8f94a3"
                                        elide: Text.ElideRight
                                        font.family: "Inter"
                                        font.pixelSize: 12
                                    }
                                }

                                HoverHandler {
                                    id: rowHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: Quickshell.execDetached(["xdg-open", headline.modelData.link])
                                }
                            }
                        }
                    }
                }
            }

            // Click-drag sideways; release past a third of a page (or a quick
            // flick) to turn it. The ends rubber-band instead of moving.
            DragHandler {
                id: swipe
                target: null
                xAxis.enabled: true
                yAxis.enabled: false

                onActiveTranslationChanged: {
                    const atEnd = (card.pageIndex === 0 && activeTranslation.x > 0)
                        || (card.pageIndex === card.sections.length - 1 && activeTranslation.x < 0);
                    viewport.dragOffset = atEnd ? activeTranslation.x / 4 : activeTranslation.x;
                }

                onActiveChanged: {
                    if (active)
                        return;
                    const offset = viewport.dragOffset;
                    const quick = Math.abs(centroid.velocity.x) > 600;
                    viewport.dragOffset = 0;
                    if (offset < -viewport.width / 3 || (quick && offset < -20))
                        card.go(card.pageIndex + 1);
                    else if (offset > viewport.width / 3 || (quick && offset > 20))
                        card.go(card.pageIndex - 1);
                }
            }

            // Touchpad swipes and wheel notches: one gesture, one page. The
            // pager locks after turning and unlocks once the input has been
            // quiet for a moment, so a touchpad's kinetic tail does not run
            // through every page. Negative is "onward" on both axes: a wheel
            // notch down is -120 on y, a swipe towards the next page is
            // negative on x (fingers moving left, with natural scrolling).
            //
            // A MouseArea, not a WheelHandler: on these layer surfaces a
            // WheelHandler never fired (measured with real axis events --
            // this MouseArea logged every one). No buttons, so clicks and
            // hover still reach the headlines underneath.
            MouseArea {
                id: wheel
                property real accumulated: 0
                property bool locked: false

                anchors.fill: parent
                acceptedButtons: Qt.NoButton

                onWheel: (event) => {
                    quiet.restart();
                    if (locked)
                        return;
                    const dx = event.angleDelta.x, dy = event.angleDelta.y;
                    accumulated += Math.abs(dx) > Math.abs(dy) ? dx : dy;
                    if (Math.abs(accumulated) >= 120) {
                        card.go(card.pageIndex + (accumulated < 0 ? 1 : -1));
                        accumulated = 0;
                        locked = true;
                    }
                }
            }

            Timer {
                id: quiet
                interval: 260
                onTriggered: {
                    wheel.locked = false;
                    wheel.accumulated = 0;
                }
            }
        }

        // --- Page dots ---
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            Repeater {
                model: card.sections.length

                delegate: Rectangle {
                    required property int index
                    readonly property bool current: index === card.pageIndex
                    width: current ? 20 : 6
                    height: 6
                    radius: 3
                    color: current ? card.primary : "#40ffffff"

                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
