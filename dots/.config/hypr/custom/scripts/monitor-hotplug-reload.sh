#!/usr/bin/env bash
# Re-evaluate the Lua monitor/workspace layout when an output is hotplugged.
#
# Why: ~/.config/hypr/workspaces.lua decides which monitor owns workspace 1 by
# checking `has_external_monitor`, but that check runs only when Hyprland parses
# its config (startup or `hyprctl reload`). A monitor connected after startup
# repositions correctly via the static `monitor=` rules, yet the workspace
# binding stays frozen on the laptop panel until the config is parsed again.
# Forcing a reload on monitoradded/monitorremoved re-runs the Lua so the
# external monitor reclaims workspace 1 automatically.
#
# Machine-independent: on single-monitor hosts the events never carry a second
# output, so the reload is a harmless no-op. Launched once from
# custom/execs.lua on hyprland.start. Requires `socat` to read socket2.
set -euo pipefail

socket="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

socat -U - "UNIX-CONNECT:${socket}" | while read -r line; do
    case "${line%%>>*}" in
        monitoradded | monitorremoved)
            # Give Hyprland a moment to finish registering the output before the
            # Lua re-checks has_external_monitor, then reload to re-run
            # monitors.lua / workspaces.lua.
            sleep 0.5
            hyprctl reload
            ;;
    esac
done
