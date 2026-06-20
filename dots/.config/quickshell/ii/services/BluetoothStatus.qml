pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    // Enable Bluetooth: unblock rfkill first, then power on the adapter.
    // Disable uses BlueZ only and does not rfkill-block, avoiding a hard-off state.
    function enable() {
        if (Bluetooth.defaultAdapter) {
            unblockBluetooth.running = false;
            unblockBluetooth.running = true;
        }
    }

    function disable() {
        if (Bluetooth.defaultAdapter) {
            Bluetooth.defaultAdapter.enabled = false;
        }
    }

    function toggle() {
        if (root.enabled)
            root.disable();
        else
            root.enable();
    }

    Process {
        id: unblockBluetooth
        command: ["rfkill", "unblock", "bluetooth"]
        onExited: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = true
    }

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction)
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]
}
