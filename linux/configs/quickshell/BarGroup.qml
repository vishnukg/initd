import QtQuick
import QtQuick.Layouts

// A group of related bar items -- system resources, display, connections,
// power. Purely structural: no surface of its own (the bar draws one
// island, and every item sits the same distance from the next), it just keeps
// a group's items together so the layout reads group by group.
RowLayout {
    Layout.fillHeight: true
    spacing: 4
}
