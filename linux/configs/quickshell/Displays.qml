import QtQuick
import Quickshell
import Quickshell.Io

// Monitor profiles (hyprmoncfg): the readout and the switch behind quick
// settings' Displays page. Logic only -- QuickSettings.qml draws the page and
// creates this with it, so the one `hyprmoncfg status --json` runs when the
// panel opens, not in the background.
Scope {
    id: root

    // Straight out of `hyprmoncfg status --json`: the monitor list is a
    // readout, the profile list is the choice. Both come from the one call.
    property var monitors: []
    property var profiles: []
    property bool daemonRunning: false
    property string pendingProfile: ""

    readonly property string activeProfile: {
        for (let index = 0; index < profiles.length; index++)
            if (profiles[index].active)
                return profiles[index].name;
        return "";
    }

    readonly property int enabledCount: {
        let count = 0;
        for (let index = 0; index < monitors.length; index++)
            if (monitors[index].enabled)
                count += 1;
        return count;
    }

    function refresh() {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    // hyprmoncfg owns the generated monitor config and its daemon reasserts the
    // layout on every monitor event, so switching profiles is the only sound
    // way to change resolution from here -- `hyprctl keyword monitor` would be
    // overwritten. Creating and arranging profiles stays a `hyprmoncfg tui`
    // job; this list only picks between what already exists.
    function applyProfile(name) {
        if (name === root.activeProfile)
            return;
        root.pendingProfile = name;
        applyProcess.command = [
            "hyprmoncfg", "apply", name,
            // Without a tty the confirm prompt reads EOF, reverts the profile
            // and exits 1 -- so the prompt has to be disabled outright rather
            // than answered. The safety net it provides is worth less here
            // than it looks: every profile in this list is one that was saved
            // from a layout that already worked.
            "--confirm-timeout", "0"
        ];
        applyProcess.running = true;
    }

    function monitorIcon(monitor) {
        return monitor.internal ? "󰌢" : "󰍹";
    }

    function monitorLabel(monitor) {
        // The laptop panel names itself after its panel vendor and a part
        // number ("LG Display 0x0804"), which says nothing and elides badly.
        if (monitor.internal)
            return "Built-in display";
        const model = (monitor.model || "").trim();
        const make = (monitor.make || "").trim();
        // `make` is often a registry code rather than a brand ("XXX Beyond
        // TV"), so the model alone reads better whenever it is descriptive.
        if (model !== "" && !/^0x/i.test(model))
            return model;
        if (make !== "" && model !== "")
            return make + " " + model;
        return monitor.name;
    }

    // "2560x1600@120.00Hz" -> "2560x1600 · 120 Hz · 1.33x". Refresh rate is
    // rounded because a mode string carries two decimals nobody reads.
    function monitorTag(monitor) {
        let tag = monitor.width + "x" + monitor.height;
        if (monitor.refresh_rate)
            tag += " · " + Math.round(monitor.refresh_rate) + " Hz";
        if (monitor.scale)
            tag += " · " + Math.round(monitor.scale * 100) / 100 + "x";
        return tag;
    }

    // One tooltip line per enabled display, so the bar can state the current
    // resolution without the popup being open.
    function monitorSummary() {
        let summary = "";
        for (let index = 0; index < monitors.length; index++) {
            const monitor = monitors[index];
            if (!monitor.enabled)
                continue;
            summary += "\n" + root.monitorLabel(monitor) + ": " + root.monitorTag(monitor);
        }
        return summary;
    }

    function profileTag(profile) {
        if (profile.recommended && !profile.active)
            return "Recommended";
        return profile.output_count + (profile.output_count === 1 ? " display" : " displays");
    }

    Process {
        id: statusProcess

        command: ["hyprmoncfg", "status", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "")
                    return;
                try {
                    const status = JSON.parse(text);
                    root.monitors = status.monitors || [];
                    root.profiles = status.profiles || [];
                    root.daemonRunning = !!(status.daemon && status.daemon.running);
                } catch (error) {
                    // A parse failure leaves the last good reading in place
                    // rather than blanking the bar item.
                    console.warn("hyprmoncfg status: " + error);
                }
            }
        }
    }

    Process {
        id: applyProcess

        // hyprmoncfg validates before it commits and refuses anything it
        // cannot lay out -- a profile saved against a different external
        // monitor typically fails with "layout overlaps". The popup has
        // already closed by then, so the reason has to reach the user through
        // a notification or it is lost entirely.
        stderr: StdioCollector { id: applyError }

        // Re-read rather than assume the apply took, then read again once the
        // dust settles: applying a profile changes the monitor set, which wakes
        // hyprmoncfgd's own auto-selection. A profile that does not match the
        // connected hardware can therefore apply cleanly and be swapped back a
        // moment later, and in between `hyprmoncfg status` reports no active
        // profile at all -- which the first read would otherwise leave on the
        // bar until the menu was next opened.
        onExited: function (code, status) {
            root.refresh();
            settleTimer.restart();
            if (code === 0)
                return;
            const reason = applyError.text.trim().split("\n")[0].replace(/^Error:\s*/, "");
            notifyProcess.command = [
                "notify-send", "-t", "5000", "󰍹  Display profile",
                "Could not apply \"" + root.pendingProfile + "\""
                    + (reason !== "" ? "\n" + reason : "")
            ];
            notifyProcess.running = true;
        }
    }

    Process {
        id: notifyProcess
    }

    Timer {
        id: settleTimer
        interval: 2000
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
