import QtQuick
import QtQuick.Layouts
import Quickshell

Scope {
    id: root

    required property var anchorItem
    required property var barWindow
    required property var menu

    property var menuStack: []

    function cleanLabel(label) {
        return label.replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_");
    }

    function open() {
        menuStack = [menu];
        menuOpener.menu = menu;
        popup.visible = true;
    }

    function close() {
        popup.visible = false;
        menuStack = [];
    }

    function openSubmenu(entry) {
        menuStack = menuStack.concat([entry]);
        menuOpener.menu = entry;
    }

    function goBack() {
        if (menuStack.length <= 1)
            return;
        menuStack = menuStack.slice(0, -1);
        menuOpener.menu = menuStack[menuStack.length - 1];
    }

    QsMenuOpener {
        id: rootMenuOpener
        menu: root.menu
    }

    QsMenuOpener {
        id: menuOpener
        menu: root.menu
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        grabFocus: true
        implicitWidth: 310
        implicitHeight: Math.min(menuColumn.implicitHeight + 12, 620)

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

            Flickable {
                anchors.fill: parent
                anchors.margins: 6
                contentHeight: menuColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: menuColumn

                    width: parent.width
                    spacing: 1

                    Rectangle {
                        visible: root.menuStack.length > 1
                        width: parent.width
                        height: visible ? 34 : 0
                        radius: 7
                        color: backHover.hovered ? "#18ffffff" : "transparent"

                        Row {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 10
                            }
                            spacing: 9

                            Text {
                                text: "‹"
                                color: "#8fb7e8"
                                font.family: "Berkeley Mono"
                                font.pixelSize: 22
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Back"
                                color: "#e8eaf0"
                                font.family: "Berkeley Mono"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                        }

                        HoverHandler {
                            id: backHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: root.goBack()
                        }
                    }

                    Repeater {
                        model: menuOpener.children

                        delegate: Item {
                            id: entry

                            required property var modelData
                            width: menuColumn.width
                            height: modelData.isSeparator ? 9 : 34

                            Rectangle {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 8
                                    rightMargin: 8
                                }
                                visible: entry.modelData.isSeparator
                                height: 1
                                color: "#18ffffff"
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: !entry.modelData.isSeparator
                                radius: 7
                                color: entryHover.hovered && entry.modelData.enabled
                                    ? "#18ffffff"
                                    : "transparent"

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
                                visible: !entry.modelData.isSeparator
                                spacing: 9

                                Item {
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18

                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: entry.modelData.buttonType !== QsMenuButtonType.None
                                        width: 14
                                        height: 14
                                        radius: entry.modelData.buttonType === QsMenuButtonType.RadioButton ? 7 : 4
                                        color: entry.modelData.checkState === Qt.Checked
                                            ? "#8fb7e8"
                                            : "transparent"
                                        border.width: 1
                                        border.color: entry.modelData.checkState === Qt.Checked
                                            ? "#8fb7e8"
                                            : "#656a78"
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.cleanLabel(entry.modelData.text)
                                    color: entry.modelData.enabled ? "#e8eaf0" : "#656a78"
                                    elide: Text.ElideRight
                                    font.family: "Berkeley Mono"
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }

                                Text {
                                    visible: entry.modelData.hasChildren
                                    text: "›"
                                    color: "#8fb7e8"
                                    font.family: "Berkeley Mono"
                                    font.pixelSize: 21
                                }
                            }

                            HoverHandler {
                                id: entryHover
                                enabled: !entry.modelData.isSeparator && entry.modelData.enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }

                            TapHandler {
                                enabled: !entry.modelData.isSeparator && entry.modelData.enabled
                                onTapped: {
                                    if (entry.modelData.hasChildren) {
                                        root.openSubmenu(entry.modelData);
                                    } else {
                                        entry.modelData.triggered();
                                        root.close();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
