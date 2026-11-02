import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Workspace overview ($mod+o): every workspace on the focused monitor as a
// miniature screen, each window a still preview where it sits. Click a window
// to focus it, a workspace to switch to it; Esc or a click on the backdrop
// closes. shell.qml creates this through a LazyLoader only while open, and
// the previews are single frames (`live: false`) -- the captures exist while
// the overview is up and are freed with it, nothing runs once it closes.
PanelWindow {
    id: overview

    required property var shell

    readonly property var monitor: Hyprland.focusedMonitor
    readonly property real monitorScale: monitor ? monitor.scale : 1
    // The monitor in layout (logical) pixels: the space window positions use.
    readonly property real logicalWidth: monitor ? monitor.width / monitorScale : 1920
    readonly property real logicalHeight: monitor ? monitor.height / monitorScale : 1200
    readonly property real mini: 0.24
    readonly property var workspaces: Hyprland.workspaces.values
        .filter(w => w.id > 0 && w.monitor && monitor && w.monitor.name === monitor.name)
        .sort((a, b) => a.id - b.id)

    function close() {
        shell.overviewOpen = false;
    }

    color: "#66000000"
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "quickshell-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Window positions come from Hyprland's client list; refresh it once on
    // open so they are current.
    Component.onCompleted: Hyprland.refreshToplevels()

    MouseArea {
        anchors.fill: parent
        onClicked: overview.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: overview.close()
    }

    Flow {
        id: grid
        anchors.centerIn: parent
        width: Math.min(parent.width - 120,
            Math.min(3, overview.workspaces.length) * (overview.logicalWidth * overview.mini + spacing))
        spacing: 28

        Repeater {
            model: overview.workspaces

            delegate: Column {
                id: workspaceView

                required property var modelData
                readonly property bool current: overview.monitor && overview.monitor.activeWorkspace === modelData
                spacing: 8

                Rectangle {
                    id: screen
                    width: overview.logicalWidth * overview.mini
                    height: overview.logicalHeight * overview.mini
                    radius: 16
                    color: Theme.menu
                    border.width: workspaceView.current ? 2 : 1
                    border.color: workspaceView.current ? Theme.accent : "#24ffffff"
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            overview.shell.activateWorkspace(workspaceView.modelData.id);
                            overview.close();
                        }
                    }

                    Repeater {
                        model: workspaceView.modelData.toplevels.values

                        delegate: Rectangle {
                            id: win

                            required property var modelData
                            readonly property var ipc: modelData.lastIpcObject || {}
                            readonly property var at: ipc.at || [0, 0]
                            readonly property var size: ipc.size || [0, 0]

                            visible: size[0] > 0 && size[1] > 0
                            x: (at[0] - (overview.monitor ? overview.monitor.x / overview.monitorScale : 0)) * overview.mini
                            y: (at[1] - (overview.monitor ? overview.monitor.y / overview.monitorScale : 0)) * overview.mini
                            width: size[0] * overview.mini
                            height: size[1] * overview.mini
                            radius: 8
                            color: "#1affffff"
                            border.width: winHover.hovered ? 2 : 0
                            border.color: Theme.accent
                            clip: true

                            ScreencopyView {
                                anchors.fill: parent
                                anchors.margins: 1
                                captureSource: win.modelData.wayland
                                live: false
                            }

                            HoverHandler {
                                id: winHover
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (win.ipc.address)
                                        Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + win.ipc.address + "\" })");
                                    overview.close();
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Workspace " + workspaceView.modelData.id
                        + (workspaceView.modelData.toplevels.values.length === 0 ? "  ·  empty" : "")
                    color: workspaceView.current ? Theme.accent : Theme.textMuted
                    font.family: "Inter"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
