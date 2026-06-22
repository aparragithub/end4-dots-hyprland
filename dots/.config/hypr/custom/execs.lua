hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprland-session.service")
    -- Reload Hyprland on monitor hotplug so workspaces.lua re-binds workspace 1
    -- to the external monitor when it connects after startup.
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/monitor-hotplug-reload.sh")
end)
