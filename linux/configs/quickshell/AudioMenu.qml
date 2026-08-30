import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Scope {
    id: root

    required property var anchorItem
    required property var barWindow
    // The default sink, already bound by shell.qml's PwObjectTracker, so
    // `audio.muted` here is live rather than a stale registry value.
    required property var sink

    readonly property var outputs: root.endpoints(true)
    readonly property var inputs: root.endpoints(false)

    // ALSA port name -> { attached: bool, name: string }, e.g.
    // { HDMI1: { attached: true, name: "Beyond TV" } }. Empty until
    // portProcess has run, which is why every lookup below fails open: an
    // endpoint the map says nothing about is shown, never hidden.
    property var ports: ({})

    function open() {
        // Monitors come and go without the sink nodes changing -- all three
        // HDMI sinks exist whether or not anything is plugged into them -- so
        // there is no PipeWire signal to hang this off. Re-read on open, which
        // is the only moment the ports are actually looked at.
        if (!portProcess.running)
            portProcess.running = true;
        popup.visible = true;
    }

    function close() {
        popup.visible = false;
    }

    // Pipewire.nodes carries everything the graph knows about: per-application
    // streams, the two halves of every filter chain, video nodes. A device
    // picker wants endpoints only, so match the composite AudioSink/AudioSource
    // flags (a duplex device carries both and shows up in both lists) and drop
    // anything flagged as a stream.
    function endpoints(wantSink) {
        const wanted = wantSink ? PwNodeType.AudioSink : PwNodeType.AudioSource;
        const nodes = Pipewire.nodes.values;
        const result = [];
        for (let index = 0; index < nodes.length; index++) {
            const node = nodes[index];
            if (node.isStream || (node.type & wanted) !== wanted)
                continue;
            // An empty port is a dead row -- there is no display on the other
            // end of it to send audio to. The current default is kept
            // regardless, so the checkmark always has somewhere to sit even if
            // the display it points at has just been unplugged.
            if (!root.isAttached(node) && !root.isDefault(node, wantSink))
                continue;
            result.push(node);
        }
        // Built-in hardware first and virtual endpoints last, with the kinds
        // clustered in between, so the laptop's own speaker/mic keeps a stable
        // position no matter what is plugged in or paired at the time.
        result.sort(function (a, b) {
            const rank = root.kindRank(a) - root.kindRank(b);
            if (rank !== 0)
                return rank;
            return root.deviceLabel(a).localeCompare(root.deviceLabel(b));
        });
        return result;
    }

    // Classified off the node name, which is the one field PipeWire fills in
    // consistently for every backend; `properties` would be richer but is only
    // populated for nodes bound by a PwObjectTracker, and this list is not.
    // Order matters: HDMI and USB endpoints are ALSA devices too, so they have
    // to be recognised before the generic alsa_ test claims them as built-in.
    function deviceKind(node) {
        const name = (node.name || "").toLowerCase();
        if (name.indexOf("bluez") !== -1)
            return "Bluetooth";
        if (name.indexOf("raop") !== -1)
            return "AirPlay";
        if (name.indexOf("hdmi") !== -1 || name.indexOf("displayport") !== -1)
            return "HDMI";
        if (name.indexOf("usb") !== -1)
            return "USB";
        if (name.indexOf("alsa_") !== -1)
            return "Built-in";
        return "Virtual";
    }

    function kindRank(node) {
        const order = ["Built-in", "USB", "HDMI", "Bluetooth", "AirPlay", "Virtual"];
        const index = order.indexOf(root.deviceKind(node));
        return index === -1 ? order.length : index;
    }

    function deviceIcon(node, isOutput) {
        switch (root.deviceKind(node)) {
        case "Bluetooth":
            return "󰂯";
        case "AirPlay":
            return "󰄙";
        case "HDMI":
            return "󰟡";
        case "USB":
            return "󰔳";
        case "Virtual":
            return "󰘮";
        default:
            return isOutput ? "󰓃" : "󰍬";
        }
    }

    // Prefer the attached display's own name over "HDMI 1". Falling back:
    // node.nickname is the short human name ("Speaker", "HDMI 1"); description
    // repeats the sound card in front of it and network sinks set neither.
    function deviceLabel(node) {
        if (!node)
            return "Unknown";
        const display = root.displayName(node);
        if (display !== "")
            return display;
        return node.nickname || node.description || node.name;
    }

    // ALSA endpoint names embed the port between double underscores
    // (`...HiFi__HDMI1__sink`), and that token is the key audio-ports.sh
    // reports under. Non-greedy, because a port name may contain a single
    // underscore of its own. Everything with no port at all -- Bluetooth,
    // AirPlay, filter chains -- returns null and is therefore always attached
    // and never renamed.
    function portFor(node) {
        const match = /__(.+?)__/.exec(node.name || "");
        if (!match)
            return null;
        return root.ports[match[1]] || null;
    }

    function displayName(node) {
        const port = root.portFor(node);
        return port ? port.name : "";
    }

    function isAttached(node) {
        const port = root.portFor(node);
        return port ? port.attached : true;
    }

    function isDefault(node, isOutput) {
        const current = isOutput ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource;
        return !!current && current.id === node.id;
    }

    function selectDevice(node, isOutput) {
        if (isOutput)
            Pipewire.preferredDefaultAudioSink = node;
        else
            Pipewire.preferredDefaultAudioSource = node;
        root.close();
    }

    // Emits `<port>|<availability>|<display name>` per card port; see the
    // script for why this cannot be read out of the Pipewire service.
    Process {
        id: portProcess

        command: [Quickshell.env("HOME") + "/.config/audio-ports.sh"]

        stdout: StdioCollector {
            onStreamFinished: {
                const ports = {};
                const lines = text.trim().split("\n");
                for (let index = 0; index < lines.length; index++) {
                    const fields = lines[index].split("|");
                    if (fields.length !== 3 || fields[0] === "")
                        continue;
                    // Only an explicit "not available" means nothing is
                    // attached: a port that cannot detect presence reports
                    // "availability unknown" and has to stay in the list.
                    ports[fields[0]] = {
                        attached: fields[1] !== "not available",
                        name: fields[2]
                    };
                }
                root.ports = ports;
            }
        }
    }

    // The bar tooltip names the current output too, so the map has to be warm
    // before the menu is ever opened.
    Component.onCompleted: portProcess.running = true

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        grabFocus: true
        implicitWidth: 380
        implicitHeight: Math.min(menuColumn.implicitHeight + 28, 620)

        anchor {
            window: root.barWindow
            item: root.anchorItem
            edges: Edges.Top
            gravity: Edges.Top
            adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipY
        }

        Rectangle {
            anchors.fill: parent
            color: "#f20d0e12"
            border.width: 1
            border.color: "#24ffffff"
            radius: 14

            Flickable {
                anchors.fill: parent
                anchors.margins: 8
                contentHeight: menuColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: menuColumn

                    width: parent.width
                    spacing: 2

                    Item {
                        width: parent.width
                        height: 36

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: "Output"
                            color: "#656a78"
                            font.family: "Berkeley Mono"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            anchors {
                                right: parent.right
                                rightMargin: 2
                                verticalCenter: parent.verticalCenter
                            }
                            visible: !!(root.sink && root.sink.audio)
                            width: muteRow.implicitWidth + 18
                            height: 28
                            radius: 7
                            color: muteHover.hovered ? "#18ffffff" : "transparent"

                            Row {
                                id: muteRow
                                anchors.centerIn: parent
                                spacing: 7

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.sink && root.sink.audio && root.sink.audio.muted
                                        ? "󰝟"
                                        : "󰕾"
                                    color: root.sink && root.sink.audio && root.sink.audio.muted
                                        ? "#52566a"
                                        : "#e8eaf0"
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 17
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.sink && root.sink.audio
                                        ? Math.round(root.sink.audio.volume * 100) + "%"
                                        : "--%"
                                    color: root.sink && root.sink.audio && root.sink.audio.muted
                                        ? "#52566a"
                                        : "#e8eaf0"
                                    font.family: "Berkeley Mono"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }

                            HoverHandler {
                                id: muteHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: {
                                    if (root.sink && root.sink.audio)
                                        root.sink.audio.muted = !root.sink.audio.muted;
                                }
                            }
                        }
                    }

                    Repeater {
                        model: root.outputs

                        delegate: MenuRow {
                            required property var modelData
                            width: menuColumn.width
                            icon: root.deviceIcon(modelData, true)
                            label: root.deviceLabel(modelData)
                            tag: root.deviceKind(modelData)
                            checked: root.isDefault(modelData, true)
                            onActivated: root.selectDevice(modelData, true)
                        }
                    }

                    Item {
                        width: parent.width
                        height: root.outputs.length > 0 ? 10 : 0
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 16
                        height: 1
                        color: "#18ffffff"
                    }

                    Item {
                        width: parent.width
                        height: 34

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: "Input"
                            color: "#656a78"
                            font.family: "Berkeley Mono"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    Repeater {
                        model: root.inputs

                        delegate: MenuRow {
                            required property var modelData
                            width: menuColumn.width
                            icon: root.deviceIcon(modelData, false)
                            label: root.deviceLabel(modelData)
                            tag: root.deviceKind(modelData)
                            checked: root.isDefault(modelData, false)
                            onActivated: root.selectDevice(modelData, false)
                        }
                    }

                    Text {
                        visible: root.inputs.length === 0
                        width: parent.width
                        height: visible ? 30 : 0
                        leftPadding: 10
                        verticalAlignment: Text.AlignVCenter
                        text: "No input devices"
                        color: "#656a78"
                        font.family: "Berkeley Mono"
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
