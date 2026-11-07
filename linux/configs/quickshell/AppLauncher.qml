import QtQuick
import Quickshell

// One launcher at the bar's left end: a Nerd Font glyph in a soft pastel
// from the workspace palette, rather than the app's full-colour theme icon,
// which read as clutter beside the rest. The tint marks the launchers as their
// own group; it is the one place colour on the bar is not state.
// Apps start through their desktop entry, so they get the same Exec line as
// rofi and xdg-open -- the shadowed entries in ~/.local/share/applications
// included (Brave's 120% scaling, Ghostty without --gtk-single-instance).
Rectangle {
    id: root

    property string desktopId: ""
    property string glyph: ""
    property color tint: Theme.text
    // Per glyph, as in BarItem: Material Design glyphs fill very different
    // shares of their em box.
    property int iconSize: 22
    property var barWindow: null

    // Looked up in the applications list itself rather than with byId():
    // the index is filled asynchronously after startup, and only this list
    // notifies, so a byId() binding would run once, find nothing, and never
    // re-run.
    readonly property var entry: DesktopEntries.applications.values
        .find(application => application.id === desktopId) || null

    // A desktopId whose app is not installed draws nothing rather than an
    // empty slot.
    visible: entry !== null
    implicitWidth: 24 + 18
    implicitHeight: 31
    radius: 8
    color: hover.hovered ? "#18ffffff" : "transparent"

    Behavior on color {
        ColorAnimation { duration: 140 }
    }

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.tint
        font.family: "FiraCode Nerd Font"
        font.pixelSize: root.iconSize
        font.weight: Font.Medium
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: if (root.entry) root.entry.execute()
    }

    BarTooltip {
        anchorItem: root
        barWindow: root.barWindow
        title: root.entry ? root.entry.name : ""
        active: hover.hovered
    }
}
