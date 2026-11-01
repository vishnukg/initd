import QtQuick
import QtQuick.Layouts

// The divider between bar groups: a 1px vertical hairline that fades out at
// both ends, so it marks a boundary without reading as a drawn line. Chosen
// over group pills (seven rounded surfaces in a row read as busy), dots
// (weaker, and they echo the clock's own "·") and floating islands (heavy)
// -- see ~/Pictures/bar-mockups for the comparison that picked it.
Rectangle {
    Layout.preferredWidth: 1
    Layout.preferredHeight: 20
    Layout.alignment: Qt.AlignVCenter
    // Items already carry 9px of hover padding each side, so a small margin
    // is enough to make a group boundary read wider than an item gap.
    Layout.leftMargin: 2
    Layout.rightMargin: 2

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#00ffffff" }
        GradientStop { position: 0.5; color: "#40ffffff" }
        GradientStop { position: 1.0; color: "#00ffffff" }
    }
}
