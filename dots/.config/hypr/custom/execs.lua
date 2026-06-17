hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprland-session.service")
end)
