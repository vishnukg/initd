import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

Scope {
    id: root

    required property var anchorItem
    required property var barWindow
    required property var menu
    property bool inlineAvailableNetworks: false

    property var menuStack: []
    readonly property var currentOpener: menuStack.length > 0
        ? menuStack[menuStack.length - 1] : null
    property real openHeight: 180
    readonly property var availableMenu: {
        if (!inlineAvailableNetworks || menuStack.length !== 1 || !currentOpener)
            return null;
        const entries = currentOpener.children.values;
        for (const entry of entries) {
            if (entry.hasChildren && cleanLabel(entry.text).toLowerCase() === "available networks")
                return entry;
        }
        return null;
    }
    readonly property var displayEntries: {
        if (!currentOpener)
            return [];
        const entries = currentOpener.children.values;
        const networks = availableOpener.children.values;
        let result = [];
        for (const entry of entries) {
            result.push(entry);
            if (entry === availableMenu)
                result = result.concat(networks);
        }
        return result;
    }

    // Bind to the current entry so a scan that rebuilds NetworkManager's
    // menu also replaces the opener; never retain a stale network submenu.
    QsMenuOpener {
        id: availableOpener
        menu: root.availableMenu
    }

    function cleanLabel(label) {
        return label.replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_");
    }

    function open() {
        if (popup.visible) {
            close();
            return;
        }
        if (!menu)
            return;
        openHeight = 180;
        openSubmenu(menu);
        popup.visible = true;
        focusGrab.active = true;
    }

    function close() {
        focusGrab.active = false;
        popup.visible = false;
        const oldStack = menuStack;
        menuStack = [];
        for (let i = oldStack.length - 1; i >= 0; i--)
            oldStack[i].destroy();
    }

    function openSubmenu(entry) {
        // Keep each ancestor open while browsing its children. Releasing an
        // opener can unload the entries referenced by a deeper submenu.
        const opener = openerComponent.createObject(root, { menu: entry });
        menuStack = menuStack.concat([opener]);
        menuScroll.contentY = 0;
    }

    function goBack() {
        if (menuStack.length <= 1)
            return;
        const oldOpener = currentOpener;
        menuStack = menuStack.slice(0, -1);
        oldOpener.destroy();
        menuScroll.contentY = 0;
    }

    Component {
        id: openerComponent
        QsMenuOpener {}
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [popup, root.barWindow]
        onCleared: root.close()
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        // Hyprland's grab survives pointer movement between the bar and menu,
        // and dismisses on an outside click instead of incidental focus loss.
        grabFocus: false
        implicitWidth: 310
        implicitHeight: root.openHeight

        anchor {
            window: root.barWindow
            item: root.anchorItem
            edges: Edges.Top
            gravity: Edges.Top
            adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipY
        }

        Rectangle {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.close()
            color: "#f20d0e12"
            border.width: 1
            border.color: "#24ffffff"
            radius: 12

            Flickable {
                id: menuScroll
                anchors.fill: parent
                anchors.margins: 6
                contentWidth: width
                contentHeight: menuColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: menuColumn

                    width: parent.width
                    spacing: 1
                    // DBus menu updates can briefly empty the list. Never
                    // collapse the popup under the pointer during this visit.
                    onImplicitHeightChanged: {
                        if (root.menuStack.length > 0)
                            root.openHeight = Math.max(root.openHeight,
                                Math.min(implicitHeight + 12, 620));
                    }

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
                                font.family: "Inter"
                                font.pixelSize: 22
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Back"
                                color: "#e8eaf0"
                                font.family: "Inter"
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
                        model: root.displayEntries

                        delegate: Item {
                            id: entry

                            required property var modelData
                            readonly property bool inlineHeader: modelData === root.availableMenu
                            readonly property bool interactive: !modelData.isSeparator
                                && modelData.enabled && !inlineHeader
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
                                color: entryHover.hovered && entry.interactive
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
                                        + (entry.inlineHeader && availableOpener.children.values.length === 0
                                            ? " — none reported" : "")
                                    color: entry.interactive ? "#e8eaf0" : "#656a78"
                                    elide: Text.ElideRight
                                    font.family: "Inter"
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }

                                Text {
                                    visible: entry.modelData.hasChildren && !entry.inlineHeader
                                    text: "›"
                                    color: "#8fb7e8"
                                    font.family: "Inter"
                                    font.pixelSize: 21
                                }
                            }

                            HoverHandler {
                                id: entryHover
                                enabled: entry.interactive
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }

                            TapHandler {
                                enabled: entry.interactive
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
