pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, CPU, GPU, and temperatures.
 */
Singleton {
    id: root
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property real gpuUsage: 0
    property bool gpuAvailable: false
    property real cpuTemperature: -1
    property real gpuTemperature: -1
    property var previousCpuStats

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

	Timer {
		interval: 1
        running: true 
        repeat: true
		onTriggered: {
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            // Parse CPU usage
            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            if (!sensorProc.running) {
                sensorProc.exec(["bash", "-c", sensorCommand])
            }

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

	FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }

    readonly property string sensorCommand: String.raw`
cpu_temp=""
for f in /sys/class/hwmon/hwmon*/temp*_input; do
    [ -r "$f" ] || continue
    label_file="$(printf '%s' "$f" | sed 's/_input$/_label/')"
    label="$(cat "$label_file" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    name="$(cat "$(dirname "$f")/name" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    case "$label $name" in
        *cpu*|*package*|*k10temp*|*coretemp*) cpu_temp="$(( $(cat "$f") / 1000 ))"; break ;;
    esac
done

gpu_usage=""
gpu_temp=""
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia_out="$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1)"
    gpu_usage="$(printf '%s' "$nvidia_out" | cut -d, -f1 | tr -dc '0-9')"
    gpu_temp="$(printf '%s' "$nvidia_out" | cut -d, -f2 | tr -dc '0-9')"
fi

if [ -z "$gpu_usage" ]; then
    for f in /sys/class/drm/card*/device/gpu_busy_percent; do
        [ -r "$f" ] || continue
        gpu_usage="$(cat "$f" 2>/dev/null | tr -dc '0-9')"
        [ -n "$gpu_usage" ] && break
    done
fi

# Intel iGPU: no gpu_busy_percent in sysfs, sample the i915 PMU via intel_gpu_top.
# Requires intel-gpu-tools and cap_perfmon on the binary (perf_event_paranoid gated).
if [ -z "$gpu_usage" ] && command -v intel_gpu_top >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    gpu_usage="$(intel_gpu_top -J -s 200 -n 2 -o - 2>/dev/null \
        | jq -r '(if type=="array" then .[-1] else . end) | [.engines[].busy] | max | floor' 2>/dev/null \
        | tr -dc '0-9')"
fi

if [ -z "$gpu_temp" ]; then
    for f in /sys/class/drm/card*/device/hwmon/hwmon*/temp*_input /sys/class/hwmon/hwmon*/temp*_input; do
        [ -r "$f" ] || continue
        label_file="$(printf '%s' "$f" | sed 's/_input$/_label/')"
        label="$(cat "$label_file" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        name="$(cat "$(dirname "$f")/name" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        case "$label $name" in
            *gpu*|*amdgpu*|*radeon*|*nvidia*) gpu_temp="$(( $(cat "$f") / 1000 ))"; break ;;
        esac
    done
fi

# Intel iGPU has no dedicated temperature sensor (it shares the CPU die).
# When usage came from intel_gpu_top, report the package temperature instead.
if [ -z "$gpu_temp" ] && command -v intel_gpu_top >/dev/null 2>&1; then
    for z in /sys/class/thermal/thermal_zone*; do
        [ "$(cat "$z/type" 2>/dev/null)" = "x86_pkg_temp" ] || continue
        gpu_temp="$(( $(cat "$z/temp" 2>/dev/null) / 1000 ))"
        break
    done
fi

[ -n "$gpu_usage" ] || gpu_usage="--"
[ -n "$cpu_temp" ] || cpu_temp="--"
[ -n "$gpu_temp" ] || gpu_temp="--"
printf '%s|%s|%s\n' "$gpu_usage" "$cpu_temp" "$gpu_temp"
`

    Process {
        id: sensorProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|")
                const gpu = Number(parts[0])
                const cpuTemp = Number(parts[1])
                const gpuTemp = Number(parts[2])

                root.gpuAvailable = Number.isFinite(gpu)
                root.gpuUsage = root.gpuAvailable ? Math.max(0, Math.min(1, gpu / 100)) : 0
                root.cpuTemperature = Number.isFinite(cpuTemp) ? cpuTemp : -1
                root.gpuTemperature = Number.isFinite(gpuTemp) ? gpuTemp : -1
            }
        }
    }

    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }
}
