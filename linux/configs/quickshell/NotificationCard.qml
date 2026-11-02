import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// One notification: app icon or image, app name, summary, body, and its
// action buttons. Used for the banners (Notifications.qml) and the history in
// the quick settings panel. Clicking the card runs its default action, if the
// app gave one, and dismisses it.
Rectangle {
    id: card

    required property var notification
    property bool compact: false
    // Hovered: the banner timer pauses while the pointer is on the card.
    readonly property bool hovered: hover.hovered
    signal closed()

    readonly property string iconSource: {
        const n = notification;
        if (!n)
            return "";
        if (n.image)
            return n.image;
        if (n.appIcon)
            return n.appIcon.startsWith("/") || n.appIcon.startsWith("file:")
                ? n.appIcon : Quickshell.iconPath(n.appIcon, true);
        return "";
    }
    readonly property var defaultAction: {
        const actions = notification ? notification.actions : [];
        for (let i = 0; i < actions.length; i++)
            if (actions[i].identifier === "default")
                return actions[i];
        return null;
    }
    readonly property var buttons: notification
        ? notification.actions.filter(action => action.identifier !== "default" && action.text) : []

    implicitHeight: content.implicitHeight + 28
    radius: 20
    color: Theme.menu
    border.width: 1
    border.color: notification && notification.urgency === NotificationUrgency.Critical
        ? Theme.bad : "#24ffffff"

    HoverHandler {
        id: hover
        cursorShape: card.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: card.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (card.defaultAction)
                card.defaultAction.invoke();
            if (card.notification)
                                card.notification.dismiss();
            card.closed();
        }
    }

    RowLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12

        // Icon: the app's (theme lookup) or the notification's own image.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: 12
            color: "#14ffffff"
            clip: true

            Image {
                anchors.fill: parent
                anchors.margins: card.notification && card.notification.image ? 0 : 6
                source: card.iconSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 80
                sourceSize.height: 80
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: card.iconSource === ""
                text: "\u{f009a}"
                color: Theme.accent
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 20
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: card.notification ? (card.notification.appName || "Notification") : ""
                    color: Theme.textDim
                    elide: Text.ElideRight
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                // Close: dismiss without running anything.
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: closeHover.hovered ? "#24ffffff" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0156}"
                        color: Theme.textMuted
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 14
                    }

                    HoverHandler {
                        id: closeHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (card.notification)
                                card.notification.dismiss();
                            card.closed();
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: card.notification ? card.notification.summary : ""
                color: Theme.text
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: "Inter"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notification ? card.notification.body : ""
                textFormat: Text.PlainText
                color: Theme.textMuted
                wrapMode: Text.Wrap
                maximumLineCount: card.compact ? 2 : 4
                elide: Text.ElideRight
                font.family: "Inter"
                font.pixelSize: 13
            }

            // Action buttons, if the app offered any besides the default.
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: card.buttons.length > 0
                spacing: 6

                Repeater {
                    model: card.buttons

                    delegate: Rectangle {
                        required property var modelData
                        implicitHeight: 28
                        implicitWidth: label.implicitWidth + 22
                        radius: 14
                        color: buttonHover.hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: parent.modelData.text
                            color: Theme.onAccent
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        HoverHandler {
                            id: buttonHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                parent.modelData.invoke();
                                if (card.notification)
                                card.notification.dismiss();
                                card.closed();
                            }
                        }
                    }
                }
            }
        }
    }
}
