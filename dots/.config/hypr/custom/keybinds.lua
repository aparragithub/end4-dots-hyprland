hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Cheatsheet (alternative to Super+/ which doesn't work on spanish layout)
hl.bind("SUPER + F1", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Shell: Toggle cheatsheet (alt)" })

-- Move window to workspace with Super+Shift+number
for i = 1, 10 do
    hl.bind("SUPER + SHIFT + " .. (i % 10), function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end, { description = "Window: Send to workspace " .. i })
end
