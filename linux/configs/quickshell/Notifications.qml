import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "bar-logic.mjs" as BarLogic

// The session's notification server (org.freedesktop.Notifications),
// replacing dunst: banners top-right under the bar, a history the quick
// settings panel lists, and Do Not Disturb.
//
// Every notification is tracked into `history` (capped, newest first) and,
// unless Do Not Disturb is on, also shown as a banner for bannerTimeout().
// Critical ones always show, and stay until dismissed. The banner window is
// created only while a banner is up.
//
// dunst stays installed as the fallback: its D-Bus activation file starts it
// if a notification arrives while qs is down, and initd-quickshell.service
// stops any such dunst before qs starts so the name comes back here.
Scope {
    id: root

    property bool doNotDisturb: false
    // Extra room above the banners: shell.qml sets it while the volume /
    // brightness indicator occupies the same corner.
    property int topOffset: 0
    // Live banners, oldest first.
    property var banners: []
    readonly property var history: server.trackedNotifications.values.slice().reverse()
    readonly property int historyLimit: 50

    function removeBanner(notification) {
        banners = banners.filter(n => n !== notification);
    }

    function clearAll() {
        const all = server.trackedNotifications.values.slice();
        for (let i = 0; i < all.length; i++)
            all[i].dismiss();
        banners = [];
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        // Plain text only: bodies render as PlainText, so markup an app sends
        // anyway shows as text rather than being interpreted.
        bodyMarkupSupported: false

        onNotification: notification => {
            notification.tracked = true;
            // Cap the history: dismiss the oldest beyond the limit.
            const tracked = server.trackedNotifications.values;
            for (let i = 0; i < tracked.length - root.historyLimit; i++)
                tracked[i].dismiss();
            const critical = notification.urgency === NotificationUrgency.Critical;
            if (!root.doNotDisturb || critical)
                root.banners = root.banners.concat([notification]).slice(-4);
        }
    }

    LazyLoader {
        active: root.banners.length > 0

        PanelWindow {
            id: window

            color: "transparent"
            focusable: false
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: 380
            implicitHeight: column.implicitHeight

            anchors {
                top: true
                right: true
            }

            margins {
                // Under the bar (4 + 39) and aligned with its right edge.
                top: 52 + root.topOffset
                right: 14
            }

            WlrLayershell.namespace: "quickshell-notifications"
            WlrLayershell.layer: WlrLayer.Overlay

            Column {
                id: column
                width: parent.width
                spacing: 10

                Repeater {
                    // A ScriptModel, not the bare array: it diffs each new
                    // array against the last, so removing one banner leaves
                    // the others' delegates -- and their running timers --
                    // alone. With the array itself, every removal rebuilt
                    // every banner and restarted all their timers.
                    model: ScriptModel {
                        values: root.banners
                    }

                    delegate: NotificationCard {
                        id: banner

                        required property var modelData
                        notification: modelData
                        width: column.width
                        compact: true
                        onClosed: root.removeBanner(modelData)

                        // Expired apps-side (CloseNotification) or dismissed
                        // from the panel: drop the banner too.
                        Connections {
                            target: banner.modelData
                            function onClosed() {
                                root.removeBanner(banner.modelData);
                            }
                        }

                        Timer {
                            readonly property int timeout: BarLogic.bannerTimeout(
                                banner.modelData.expireTimeout,
                                banner.modelData.urgency === NotificationUrgency.Critical)
                            interval: timeout
                            running: timeout > 0 && !banner.hovered
                            onTriggered: {
                                const n = banner.modelData;
                                root.removeBanner(n);
                                // Transient ones never enter the history.
                                if (n && n.transient)
                                    n.dismiss();
                            }
                        }
                    }
                }
            }
        }
    }
}
