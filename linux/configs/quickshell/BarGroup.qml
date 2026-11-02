import QtQuick
import QtQuick.Layouts

// A group of related bar items -- system resources, display, connections,
// power. Purely structural: no surface of its own (the bar draws one
// island, and every item sits the same distance from the next), it just keeps
// a group's items together so the layout reads group by group.
RowLayout {
    Layout.fillHeight: true
    // A nested Layout defaults to fillWidth: true. A group of fixed-width items
    // never grows anyway, but an EMPTY one (the tray with no apps running) has
    // no maximum width, so it split the free space with the bar's spacer: the
    // right-hand items slid toward the middle with a gap in the row.
    Layout.fillWidth: false
    spacing: 4
}
