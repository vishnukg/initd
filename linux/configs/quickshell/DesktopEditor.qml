import QtQuick
import Quickshell
import Quickshell.Wayland

// Arrange mode for the desktop widgets: a full-screen overlay with one drag
// handle per widget. It only exists while editing (right-click a widget,
// $mod+SHIFT+d, or `qs ipc call bar editDesktop`), so its screen-sized buffer
// is not paid the rest of the time. Esc or Done leaves it; every drop is
// saved at once, so there is nothing to lose by leaving.
PanelWindow {
    id: editor

    // The owning DesktopWidgets. Not called `desk`: this is created inside a
    // LazyLoader, whose nested component would resolve `desk: desk` to this
    // very property (undefined) before reaching the outer `desk` id.
    required property var host
    // The WidgetWindows to arrange.
    required property var widgets

    screen: host.screen
    color: "#40000000"
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "quickshell-desktop-editor"
    // Above windows, so it works from any workspace; Exclusive so Esc lands.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    function close() {
        editor.host.shell.desktopEditing = false;
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: editor.close()
        Keys.onReturnPressed: editor.close()
    }

    Repeater {
        model: editor.widgets

        delegate: Rectangle {
            id: handle

            required property var modelData
            readonly property var widget: modelData
            property point origin

            visible: widget.visible
            x: widget.position.x
            y: widget.position.y
            width: widget.implicitWidth
            height: widget.implicitHeight
            radius: 28
            color: drag.active ? "#33a8c7fa" : hover.hovered ? "#24a8c7fa" : "#14a8c7fa"
            border.width: 2
            border.color: drag.active ? "#d3e3fd" : "#a8c7fa"

            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
                anchors { left: parent.left; top: parent.top; margins: 12 }
                radius: height / 2
                color: "#a8c7fa"
                implicitHeight: 28
                implicitWidth: name.implicitWidth + 24

                Text {
                    id: name
                    anchors.centerIn: parent
                    text: "\u{f01be}  " + handle.widget.title
                    color: "#062e6f"
                    font.family: "Inter"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            HoverHandler {
                id: hover
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            }

            DragHandler {
                id: drag
                target: null

                onActiveChanged: {
                    if (active) {
                        handle.origin = Qt.point(handle.widget.position.x, handle.widget.position.y);
                        editor.host.dragTo(handle.widget.key, handle.origin.x, handle.origin.y);
                    } else {
                        const spot = editor.host.dragging[handle.widget.key];
                        if (spot)
                            editor.host.savePlacement(handle.widget.key, spot.x, spot.y);
                        editor.host.dragTo(handle.widget.key, null, null);
                    }
                }

                onActiveTranslationChanged: {
                    if (!active)
                        return;
                    editor.host.dragTo(handle.widget.key,
                        Math.min(Math.max(0, handle.origin.x + activeTranslation.x),
                            editor.width - handle.width),
                        Math.min(Math.max(0, handle.origin.y + activeTranslation.y),
                            editor.height - handle.height));
                }
            }
        }
    }

    // Toolbar, top centre: a hint plus Reset and Done.
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 64 }
        radius: height / 2
        color: "#e6161922"
        border.width: 1
        border.color: "#24ffffff"
        implicitHeight: 52
        implicitWidth: bar.implicitWidth + 16

        Row {
            id: bar
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 14
                rightPadding: 8
                text: "Drag widgets to arrange them"
                color: "#e8eaf0"
                font.family: "Inter"
                font.pixelSize: 15
                font.weight: Font.Medium
            }

            ToolbarButton {
                label: "Reset"
                onClicked: editor.host.resetPlacements()
            }

            ToolbarButton {
                label: "Done"
                filled: true
                onClicked: editor.close()
            }
        }
    }

    component ToolbarButton: Rectangle {
        id: button

        property string label: ""
        property bool filled: false
        signal clicked()

        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: 38
        implicitWidth: text.implicitWidth + 32
        radius: 19
        color: filled
            ? (mouse.containsMouse ? "#bdd4fb" : "#a8c7fa")
            : (mouse.containsMouse ? "#24ffffff" : "#12ffffff")

        Text {
            id: text
            anchors.centerIn: parent
            text: button.label
            color: button.filled ? "#062e6f" : "#e8eaf0"
            font.family: "Inter"
            font.pixelSize: 14
            font.weight: Font.DemiBold
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
