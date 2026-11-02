import QtQuick
import QtQuick.Effects

Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    // An icon-theme SVG instead of a font glyph, for the few items whose
    // Nerd Font glyph reads too thin beside the tray's theme icons. It is
    // tinted with `foreground` like a glyph would be, so colour still carries
    // state; the source should be a light, single-colour symbol.
    property url iconSource: ""
    property color foreground: Theme.text
    property color background: "transparent"
    property bool clickable: false
    property bool secondaryClickable: false
    property int horizontalPadding: 9
    property int iconSize: 21
    // Icon-to-text gap. Glyphs sit in a square box of iconSize, so a narrow
    // one (battery) carries wide side bearings and a full-width one
    // (brightness) none; items override this to keep ~10 device px of
    // visible gap between ink and number.
    property int iconSpacing: 6
    // Tabular (equal-width) digits, for readouts that change every tick
    // (network speed): "2.7K" -> "8.1K" then keeps the same width, so only a
    // change in the number of characters moves anything. Reserving a fixed
    // width was tried and dropped -- at typical speeds it read as a gap.
    property bool tabularDigits: false
    property var barWindow: null
    property string tooltipTitle: ""
    property string tooltipBody: ""
    signal clicked()
    signal secondaryClicked()

    implicitWidth: content.implicitWidth + horizontalPadding * 2
    implicitHeight: 31
    radius: 8
    color: hover.hovered ? "#18ffffff" : background

    Behavior on color {
        ColorAnimation { duration: 140 }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: root.icon !== "" || root.iconSource != "" ? root.iconSpacing : 0

        Item {
            visible: root.iconSource != ""
            width: visible ? root.iconSize : 0
            height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: iconImage
                anchors.fill: parent
                source: root.iconSource
                sourceSize: Qt.size(width, height)
                visible: false
            }

            MultiEffect {
                anchors.fill: iconImage
                source: iconImage
                colorization: 1.0
                colorizationColor: root.foreground
            }
        }

        Text {
            visible: root.icon !== ""
            width: visible ? root.iconSize : 0
            height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.icon
            color: root.foreground
            font.family: "FiraCode Nerd Font"
            font.pixelSize: root.iconSize
            font.weight: Font.Medium
        }

        Text {
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            font.features: root.tabularDigits ? { "tnum": 1 } : ({})
            text: root.text
            color: root.foreground
            font.family: "Inter"
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }
    }

    HoverHandler {
        id: hover
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    // Reading an item is hover-only; clicking is reserved for items that
    // actually do something (cycle the power profile, mute, open a menu).
    TapHandler {
        enabled: root.clickable
        acceptedButtons: Qt.LeftButton
        onTapped: root.clicked()
    }

    // Right-click is the escape hatch for an item whose left-click had to be
    // handed over to a dropdown: audio keeps one-click mute here.
    TapHandler {
        enabled: root.secondaryClickable
        acceptedButtons: Qt.RightButton
        onTapped: root.secondaryClicked()
    }

    BarTooltip {
        anchorItem: root
        barWindow: root.barWindow
        title: root.tooltipTitle
        body: root.tooltipBody
        active: hover.hovered
    }

}
