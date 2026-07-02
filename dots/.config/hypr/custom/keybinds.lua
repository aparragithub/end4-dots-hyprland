hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Cheatsheet (alternative to Super+/ which doesn't work on spanish layout)
hl.bind("SUPER + F1", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Shell: Toggle cheatsheet (alt)" })

-- Move window to workspace with Super+Shift+number
for i = 1, 10 do
    hl.bind("SUPER + SHIFT + " .. (i % 10), function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end, { description = "Window: Send to workspace " .. i })
end

-- Browser: Super+B
hl.unbind("SUPER + B")
hl.bind("SUPER + B", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh 'zen-browser'"), { description = "Browser: Open" })

-- Sidebar: simplificar
hl.unbind("SUPER + A")
hl.unbind("SUPER + O")
hl.unbind("SUPER + N")
hl.bind("SUPER + N", hl.dsp.global("quickshell:sidebarLeftToggle"), { description = "Shell: Left sidebar" })
hl.bind("SUPER + H", hl.dsp.global("quickshell:sidebarRightToggle"), { description = "Shell: Right sidebar" })

-- Workspace switcher: Alt+Tab
hl.bind("ALT + Tab", hl.dsp.focus({ workspace = "m+1" }), { description = "Workspace: Focus next occupied" })
hl.bind("ALT + SHIFT + Tab", hl.dsp.focus({ workspace = "m-1" }), { description = "Workspace: Focus previous occupied" })

-- Voice dictation: whisper.cpp push-to-talk (types into the focused window)
-- Replaces the stock dsnote shortcut (dsnote uninstalled).
hl.unbind("SUPER + SHIFT + D")
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/dictation-toggle.sh"), { description = "Dictation: Toggle voice typing (whisper)" })
