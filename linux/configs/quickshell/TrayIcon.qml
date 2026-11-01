import QtQuick
import QtQuick.Layouts
import Quickshell
import "bar-logic.mjs" as BarLogic

// One StatusNotifierItem in the bar. shell.qml lays these out in two filtered
// Repeaters -- nm-applet, then the native Bluetooth item, then everything else
// -- which is why the delegate is its own file rather than inline.
Item {
    id: trayItem

    required property var modelData
    required property var barWindow
    property bool wifiConnected: false

    readonly property bool networkApplet: BarLogic.trayRole(modelData.id, modelData.title) === "network"

    // Same footprint as a BarItem: icon plus 9px padding each side, so the gaps
    // through the tray match the gaps between every other item. The Wi-Fi SVG
    // carries more empty margin than an app's tray icon, so it is drawn larger
    // to land on the same ~22 device px of ink as the glyph icons.
    readonly property int iconSize: networkApplet ? 23 : 19

    Layout.preferredWidth: iconSize + 18
    Layout.fillHeight: true

    Image {
        anchors.centerIn: parent
        width: trayItem.iconSize
        height: trayItem.iconSize
        source: trayItem.networkApplet
            ? (trayItem.wifiConnected
                ? "file:///usr/share/icons/Papirus-Dark/16x16/devices/network-wireless.svg"
                : Qt.resolvedUrl("icons/network-wireless-empty.svg"))
            : trayItem.modelData.icon
        sourceSize: Qt.size(width, height)
    }

    QsMenuAnchor {
        id: trayMenu
        menu: trayItem.modelData.menu
        anchor.item: trayItem
    }

    TrayMenu {
        id: modernMenu
        anchorItem: trayItem
        barWindow: trayItem.barWindow
        menu: trayItem.modelData.menu
        inlineAvailableNetworks: trayItem.networkApplet
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            if (trayItem.networkApplet) {
                modernMenu.open();
            } else if (trayItem.modelData.hasMenu && trayItem.modelData.onlyMenu) {
                trayMenu.open();
            } else {
                trayItem.modelData.activate();
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            if (trayItem.networkApplet) {
                modernMenu.open();
            } else if (trayItem.modelData.hasMenu) {
                trayMenu.open();
            } else {
                trayItem.modelData.secondaryActivate();
            }
        }
    }
}
