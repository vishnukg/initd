import QtQuick
import Quickshell
import Quickshell.Wayland
import "bar-logic.mjs" as BarLogic

// One desktop widget in its own layer surface, sized to the widget and placed
// by margins from the top-left corner. Tight surfaces keep the cost to the
// widgets' own pixels: one full-screen surface for all of them measured
// +56 MB of GPU memory, and Hyprland would blur the whole screen-sized layer
// on every redraw. Moving happens in DesktopEditor.qml; right-click opens it.
PanelWindow {
    id: window

    required property string key
    property string title: key
    required property var desk
    property real defaultX: 0
    property real defaultY: 0
    default property alias content: holder.data
    readonly property Item body: holder.children.length > 0 ? holder.children[0] : null

    // Saved spot (or the default), snapped and kept on screen. While the
    // editor drags this widget, it follows the drag live instead.
    readonly property var placed: BarLogic.placeWidget(
        desk.placements[desk.placementKey(key)],
        { x: defaultX, y: defaultY },
        { width: implicitWidth, height: implicitHeight },
        { width: screen ? screen.width : 0, height: screen ? screen.height : 0 })
    readonly property var live: desk.dragging[key]
    readonly property var position: live || placed

    screen: desk.screen
    color: "transparent"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: body ? body.width : 1
    implicitHeight: body ? body.height : 1

    anchors {
        top: true
        left: true
    }

    margins {
        left: Math.round(window.position.x)
        top: Math.round(window.position.y)
    }

    WlrLayershell.namespace: "quickshell-desktop"
    WlrLayershell.layer: WlrLayer.Bottom

    Item {
        id: holder
        anchors.fill: parent
    }

    // Right-click anywhere on a widget to arrange them, the way a long-press
    // on a ChromeOS/Android home screen does. Left clicks pass straight
    // through to the widget's own buttons.
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: window.desk.shell.desktopEditing = true
    }
}
