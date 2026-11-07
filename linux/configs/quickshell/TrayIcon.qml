import QtQuick
import QtQuick.Layouts
import Quickshell

// One StatusNotifierItem in the bar's tray group. shell.qml hands it only the
// items trayRole() calls "other": nm-applet and blueman keep running headless
// (NetworkManager's secret agent, BlueZ's pairing agent), and Wi-Fi and
// Bluetooth live in quick settings instead.
Item {
    id: trayItem

    required property var modelData
    required property var barWindow

    // Same footprint as a BarItem: icon plus 9px padding each side, so the gaps
    // through the tray match the gaps between every other item.
    readonly property int iconSize: 19

    Layout.preferredWidth: iconSize + 18
    Layout.fillHeight: true

    Image {
        anchors.centerIn: parent
        width: trayItem.iconSize
        height: trayItem.iconSize
        source: trayItem.modelData.icon
        sourceSize: Qt.size(width, height)
    }

    QsMenuAnchor {
        id: trayMenu
        menu: trayItem.modelData.menu
        anchor.item: trayItem
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            if (trayItem.modelData.hasMenu && trayItem.modelData.onlyMenu)
                trayMenu.open();
            else
                trayItem.modelData.activate();
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            if (trayItem.modelData.hasMenu)
                trayMenu.open();
            else
                trayItem.modelData.secondaryActivate();
        }
    }
}
