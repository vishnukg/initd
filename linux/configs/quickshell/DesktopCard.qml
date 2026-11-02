import QtQuick

// A desktop widget surface: the Material 3 "tonal card" -- large radius,
// translucent tonal fill over the blurred wallpaper (quickshell-desktop-blur
// in hyprland.lua), a hairline of light along the edge instead of a shadow.
Rectangle {
    default property alias content: inner.data
    property int padding: 20

    radius: 28
    color: "#a6161922"
    border.width: 1
    border.color: "#14ffffff"

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: parent.padding
    }
}
