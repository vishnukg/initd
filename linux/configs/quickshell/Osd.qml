import QtQuick
import Quickshell
import Quickshell.Wayland

// On-screen indicator for volume, microphone and brightness: a frosted pill at
// the bottom centre with an icon, a level bar and the percentage. shell.qml
// creates it through a LazyLoader only while a level is changing and drops it
// 1.5 s after the last change, so at rest it does not exist at all.
PanelWindow {
    id: osd

    // "volume" | "mic" | "brightness"
    property string kind: "volume"
    property real value: 0
    property bool muted: false

    readonly property string glyph: {
        if (kind === "brightness")
            return value < 0.34 ? "\u{f00de}" : value < 0.67 ? "\u{f00df}" : "\u{f00e0}";
        if (kind === "mic")
            return muted ? "\u{f036d}" : "\u{f036c}";
        if (muted || value <= 0)
            return "\u{f075f}";
        return value < 0.34 ? "\u{f057f}" : value < 0.67 ? "\u{f0580}" : "\u{f057e}";
    }
    readonly property string label: kind === "mic"
        ? (muted ? "Microphone off" : "Microphone on")
        : muted ? "Muted" : Math.round(value * 100) + "%"

    color: "transparent"
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 320
    implicitHeight: 64

    anchors.bottom: true
    margins.bottom: 96

    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.layer: WlrLayer.Overlay

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.menu
        border.width: 1
        border.color: "#24ffffff"

        Row {
            anchors.centerIn: parent
            spacing: 14

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: osd.glyph
                color: osd.muted ? Theme.textDim : Theme.accent
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 24
            }

            // The level; the mic indicator is on/off only.
            Rectangle {
                visible: osd.kind !== "mic"
                anchors.verticalCenter: parent.verticalCenter
                width: 170
                height: 6
                radius: 3
                color: "#24ffffff"

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, osd.value))
                    height: parent.height
                    radius: 3
                    color: osd.muted ? Theme.textDim : Theme.accent
                    Behavior on width { NumberAnimation { duration: 90 } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: osd.kind === "mic" ? implicitWidth : 52
                text: osd.label
                color: Theme.text
                font.family: "Inter"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }
    }
}
