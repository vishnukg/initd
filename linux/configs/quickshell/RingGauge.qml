import QtQuick
import QtQuick.Shapes

// A Material-style circular progress ring: a dim full track, a rounded arc
// for the value, an icon in the middle and the reading underneath.
Column {
    id: root

    property real value: 0
    property string icon: ""
    property string label: ""
    property string reading: ""
    property color accent: "#a8c7fa"
    property int size: 68
    property int thickness: 7

    spacing: 8

    Item {
        width: root.size
        height: root.size
        anchors.horizontalCenter: parent.horizontalCenter

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                strokeWidth: root.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.size / 2
                    centerY: root.size / 2
                    radiusX: (root.size - root.thickness) / 2
                    radiusY: radiusX
                    startAngle: 0
                    sweepAngle: 360
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: root.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.size / 2
                    centerY: root.size / 2
                    radiusX: (root.size - root.thickness) / 2
                    radiusY: radiusX
                    startAngle: -90
                    // A sliver even at 0%, so the cap still marks the start.
                    sweepAngle: Math.max(1, 360 * root.value)
                    Behavior on sweepAngle {
                        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.icon
            color: root.accent
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 22
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.reading
            color: "#e8eaf0"
            font.family: "Inter Display"
            font.pixelSize: 16
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: "#8f94a3"
            font.family: "Inter"
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
}
