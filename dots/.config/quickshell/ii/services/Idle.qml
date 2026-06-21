pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled
    inhibit: false

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance) {
                root.inhibit = Persistent.states.idle.inhibit;
            } else {
                Persistent.states.idle.inhibit = root.inhibit;
            }
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    // Belt-and-suspenders: also freeze the hypridle process while inhibiting.
    // The Wayland IdleInhibitor surface can be torn down on monitor hotplug
    // (e.g. a KVM switch), which would silently re-enable idle and let the
    // machine suspend even with the toggle on. Pausing the daemon with SIGSTOP
    // guarantees no lock/dpms/suspend can fire, independent of any surface.
    onInhibitChanged: {
        if (root.inhibit) {
            freezeIdleDaemon.running = true;
        } else {
            resumeIdleDaemon.running = true;
        }
    }

    Process {
        id: freezeIdleDaemon
        command: ["pkill", "-STOP", "hypridle"]
    }

    Process {
        id: resumeIdleDaemon
        command: ["pkill", "-CONT", "hypridle"]
    }

    IdleInhibitor {
        id: idleInhibitor
        window: PanelWindow {
            // Inhibitor requires a "visible" surface
            // Actually not lol
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}
