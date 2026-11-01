import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "bar-logic.mjs" as BarLogic

// Native Bluetooth dropdown: the adapter's power switch plus every paired
// device, click to connect or disconnect. Read straight off BlueZ's D-Bus
// objects through Quickshell.Bluetooth, so it costs no process at all.
//
// blueman stays installed and blueman-applet keeps running -- headless, with
// its StatusIcon plugin disabled by linux/setup.sh -- because it is the BlueZ
// pairing agent (PIN/passkey confirmation) and the OBEX receiver, neither of
// which Quickshell provides. What its tray menu used to offer beyond this list
// (pairing new devices, audio profiles, sending files) is one click away in
// blueman-manager, behind the "Bluetooth settings" row.
Scope {
    id: root

    required property var anchorItem
    required property var barWindow

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: !!adapter && adapter.enabled
    readonly property bool blocked: !!adapter && adapter.state === BluetoothAdapterState.Blocked

    // Paired only: an unpaired device is just something nearby that happened
    // to advertise, and connecting to it would start a pairing this menu has
    // no UI for.
    readonly property var devices: {
        const all = Bluetooth.devices.values;
        const result = [];
        for (let index = 0; index < all.length; index++)
            if (all[index].paired || all[index].bonded)
                result.push(all[index]);
        result.sort(BarLogic.compareBluetoothDevices);
        return result;
    }

    readonly property var connectedDevices: {
        const result = [];
        for (let index = 0; index < devices.length; index++)
            if (devices[index].connected)
                result.push(devices[index]);
        return result;
    }

    function open() {
        popup.visible = !popup.visible;
    }

    function close() {
        popup.visible = false;
    }

    function togglePower() {
        if (root.adapter && !root.blocked)
            root.adapter.enabled = !root.adapter.enabled;
    }

    function deviceTag(device) {
        if (device.state === BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (device.connected && device.batteryAvailable) {
            const percent = BarLogic.batteryPercent(device.battery);
            if (!isNaN(percent))
                return percent + "%";
        }
        return device.connected ? "Connected" : "";
    }

    // The menu stays open on purpose: a connect takes a second or two, and the
    // row's tag is where "Connecting…" and then the battery level show up.
    function toggleDevice(device) {
        if (device.state === BluetoothDeviceState.Connecting
                || device.state === BluetoothDeviceState.Disconnecting)
            return;
        if (device.connected)
            device.disconnect();
        else
            device.connect();
    }

    // One line per connected device, for the bar tooltip.
    function summary() {
        if (!root.adapter)
            return "No Bluetooth adapter";
        if (root.blocked)
            return "Blocked (rfkill / airplane mode)";
        if (!root.powered)
            return "Off";
        if (root.connectedDevices.length === 0)
            return "On · nothing connected";
        let text = "";
        for (let index = 0; index < root.connectedDevices.length; index++) {
            const device = root.connectedDevices[index];
            const tag = root.deviceTag(device);
            text += (index > 0 ? "\n" : "") + device.name
                + (tag !== "" && tag !== "Connected" ? " · " + tag : "");
        }
        return text;
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        grabFocus: true
        implicitWidth: 320
        implicitHeight: Math.min(menuColumn.implicitHeight + 28, 620)

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
            radius: 14

            Flickable {
                anchors.fill: parent
                anchors.margins: 8
                contentHeight: menuColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: menuColumn

                    width: parent.width
                    spacing: 2

                    Item {
                        width: parent.width
                        height: 36

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: "Bluetooth"
                            color: "#656a78"
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        // Power pill, styled like AudioMenu's mute toggle.
                        Rectangle {
                            anchors {
                                right: parent.right
                                rightMargin: 2
                                verticalCenter: parent.verticalCenter
                            }
                            visible: !!root.adapter
                            width: powerRow.implicitWidth + 18
                            height: 28
                            radius: 7
                            color: powerHover.hovered && !root.blocked ? "#18ffffff" : "transparent"

                            Row {
                                id: powerRow
                                anchors.centerIn: parent
                                spacing: 7

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.powered ? "󰂯" : "󰂲"
                                    color: root.powered ? "#8fb7e8" : "#52566a"
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 17
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.blocked ? "Blocked" : root.powered ? "On" : "Off"
                                    color: root.powered ? "#e8eaf0" : "#52566a"
                                    font.family: "Inter"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }

                            HoverHandler {
                                id: powerHover
                                cursorShape: root.blocked ? Qt.ArrowCursor : Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: root.togglePower()
                            }
                        }
                    }

                    Repeater {
                        model: root.powered ? root.devices : []

                        delegate: MenuRow {
                            required property var modelData
                            width: menuColumn.width
                            icon: BarLogic.bluetoothDeviceIcon(modelData.icon)
                            label: modelData.name || modelData.address
                            tag: root.deviceTag(modelData)
                            checked: modelData.connected
                            onActivated: root.toggleDevice(modelData)
                        }
                    }

                    Text {
                        visible: !root.powered || root.devices.length === 0
                        width: parent.width
                        height: visible ? 30 : 0
                        leftPadding: 10
                        verticalAlignment: Text.AlignVCenter
                        text: !root.adapter ? "No Bluetooth adapter"
                            : root.blocked ? "Blocked by rfkill / airplane mode"
                            : !root.powered ? "Bluetooth is off"
                            : "No paired devices"
                        color: "#656a78"
                        font.family: "Inter"
                        font.pixelSize: 13
                    }

                    Item {
                        width: parent.width
                        height: 10
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 16
                        height: 1
                        color: "#18ffffff"
                    }

                    Item {
                        width: parent.width
                        height: 4
                    }

                    MenuRow {
                        width: menuColumn.width
                        icon: "󰒓"
                        label: "Bluetooth settings…"
                        tag: "Pair · profiles · files"
                        onActivated: {
                            Quickshell.execDetached(["blueman-manager"]);
                            root.close();
                        }
                    }
                }
            }
        }
    }
}
