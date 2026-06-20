pragma Singleton
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    function closeAllWindows() {
        HyprlandData.windowList.map(w => w.pid).forEach(pid => {
            Quickshell.execDetached(["kill", pid]);
        });
    }

    function changePassword() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.changePassword}`]);
    }

    function lock() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function suspend() {
        try { MprisController.pauseAll(); } catch (e) { console.error("[Session] pauseAll before suspend failed:", e); }
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function logout() {
        closeAllWindows();
        Quickshell.execDetached(["pkill", "-i", "Hyprland"]);
    }

    function launchTaskManager() {
        Quickshell.execDetached([
            `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/scripts/launch_first_available.sh`,
            "gnome-system-monitor",
            "plasma-systemmonitor --page-name Processes",
            "command -v btop && kitty -1 fish -c btop"
        ]);
    }

    function hibernate() {
        try { MprisController.pauseAll(); } catch (e) { console.error("[Session] pauseAll before hibernate failed:", e); }
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    function poweroff() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl poweroff || loginctl poweroff`]);
    }

    function reboot() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `reboot || loginctl reboot`]);
    }

    function rebootToFirmware() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl reboot --firmware-setup || loginctl reboot --firmware-setup`]);
    }
}
