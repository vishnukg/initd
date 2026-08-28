-- Hyprland config — direct port of the old i3 config (linux/configs/i3/config),
-- later ported from hyprlang (hyprland.conf) to Lua ahead of hyprlang's planned
-- removal in Hyprland 0.57. Keybindings are kept 1:1 with i3; comments note the
-- few places where a concept has no exact Hyprland equivalent.
-- Reference: https://wiki.hypr.land/Configuring/

local mod = "SUPER"

hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Adwaita")

-- ── Monitors ──────────────────────────────────────────────────────────────────
-- Wayland replaces the whole autorandr/xsettingsd/Xft.dpi machinery with
-- per-monitor scale. 1.33333 on the laptop panel (2560x1600, ~224 PPI) — a
-- 1920x1200 logical workspace; adjust per monitor if needed. This was 1.5
-- (tuned for the old machine's panel), then 1.25, which read a touch small.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = "1.33333" })
hl.monitor({ output = "",      mode = "preferred", position = "auto", scale = "1.33333" })

-- hyprmoncfg owns the generated monitor rules, profiles, hotplug, and lid
-- handling. Its protected import keeps Hyprland usable before the first
-- profile is created; the static rules above are the fallback in that state.
pcall(require, "monitors")

-- ── Input ─────────────────────────────────────────────────────────────────────
hl.config({
    input = {
        -- setxkbmap -option ctrl:nocaps
        kb_options = "ctrl:nocaps",
        -- xset r rate 350 30
        repeat_delay = 350,
        repeat_rate = 30,

        follow_mouse = 1,
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
        },
    },
})

-- ── Autostart ─────────────────────────────────────────────────────────────────
hl.on("hyprland.start", function()
    -- Make portals (screenshare, file pickers) see the session environment.
    hl.exec_cmd("sh -c 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP && systemctl --user start initd-hyprland-session.service'")

    -- Polkit auth agent (GNOME ships its own inside gnome-shell; Hyprland needs one).
    hl.exec_cmd("lxpolkit")

    hl.exec_cmd("qs")
    hl.exec_cmd("dunst")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("nm-applet")
    -- blueman's XDG autostart only fires in sessions that reach the systemd
    -- graphical-session.target (GNOME does, this session doesn't) — start explicitly.
    hl.exec_cmd("blueman-applet")
    -- --silent: start in the background with just the tray icon, no window.
    -- Delayed so its tray icon registers after nm-applet/blueman-applet (it's
    -- an Electron app and tends to win the SNI-registration race otherwise,
    -- landing between the wifi and bluetooth icons in the system tray).
    hl.exec_cmd("bash -c 'sleep 2 && 1password --silent'")
    -- CopyQ's persisted hide_main_window setting keeps it out of the way at
    -- startup; the server still runs for $mod+c.
    hl.exec_cmd("copyq --start-server")
end)

-- ── Media / hardware keys ─────────────────────────────────────────────────────
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"),   { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"),  { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("bash -c 'brightnessctl --min-val=2 -q set 5%- && qs ipc call bar refreshBrightness'"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("bash -c 'brightnessctl -q set 5%+ && qs ipc call bar refreshBrightness'"),             { locked = true, repeating = true })

-- Screenshot (scrot → grim)
hl.bind("Print", hl.dsp.exec_cmd("bash -c 'mkdir -p \"$HOME/Pictures\" && grim \"$HOME/Pictures/screenshot-$(date +%Y-%m-%d-%H-%M-%S).png\"'"))
-- Screenshot region (select area → save + copy to clipboard)
hl.bind(mod .. " + SHIFT + s", hl.dsp.exec_cmd("bash -c 'mkdir -p \"$HOME/Pictures\" && f=\"$HOME/Pictures/screenshot-$(date +%Y-%m-%d-%H-%M-%S).png\" && grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\"'"))

-- ── Apps ──────────────────────────────────────────────────────────────────────
-- background-opacity is overridden on the command line rather than in
-- shared/configs/ghostty/config, which is shared with macOS: there the 0.58
-- default sits over a dim desktop and reads fine, while here it sits over a
-- bright painting. Ghostty accepts any config key as a CLI flag, and applies
-- it per-window even when an instance is already running.
hl.bind(mod .. " + Return", hl.dsp.exec_cmd("ghostty --background-opacity=0.92"))
hl.bind(mod .. " + SHIFT + Return", hl.dsp.exec_cmd("firefox --new-window"))
hl.bind(mod .. " + SHIFT + q", hl.dsp.window.close())
hl.bind(mod .. " + d",   hl.dsp.exec_cmd("rofi -show drun"))
hl.bind(mod .. " + Tab", hl.dsp.exec_cmd("rofi -show window"))
-- Keyboard's dedicated "Copilot" key: the kernel has no keycode for it, so
-- the firmware sends a synthetic Super+Shift+F23 chord instead (confirmed
-- via `libinput debug-events`). Wired to the same app launcher as mod+d.
hl.bind(mod .. " + SHIFT + F23", hl.dsp.exec_cmd("rofi -show drun"))
-- Clipboard history (tray-less: linux/setup.sh:disable_copyq_tray sets disable_tray=true)
hl.bind(mod .. " + c", hl.dsp.exec_cmd("copyq toggle"))

-- Toggle night light (moderately warm screen, manual only)
hl.bind(mod .. " + SHIFT + n", hl.dsp.exec_cmd("~/.config/night-light-toggle.sh"))

-- Lock now / lock-session (hypridle runs hyprlock on loginctl lock-session)
-- Ctrl+Super+Q mirrors macOS's Ctrl+Cmd+Q; $mod+Shift+X kept as the original.
hl.bind(mod .. " + CTRL + q",  hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mod .. " + SHIFT + x", hl.dsp.exec_cmd("loginctl lock-session"))

-- Re-apply monitor layout for the current hardware state
-- (autorandr --change → hyprctl reload re-evaluates the monitor rules above).
hl.bind(mod .. " + SHIFT + m", hl.dsp.exec_cmd("hyprctl reload"))

-- ── Focus / move (i3 vim keys + arrows) ──────────────────────────────────────
hl.bind(mod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + j", hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + l", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + Left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + Down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + Up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + Right", hl.dsp.focus({ direction = "right" }))

hl.bind(mod .. " + SHIFT + h", hl.dsp.window.move({ direction = "l" }))
hl.bind(mod .. " + SHIFT + j", hl.dsp.window.move({ direction = "d" }))
hl.bind(mod .. " + SHIFT + k", hl.dsp.window.move({ direction = "u" }))
hl.bind(mod .. " + SHIFT + l", hl.dsp.window.move({ direction = "r" }))
hl.bind(mod .. " + SHIFT + Left",  hl.dsp.window.move({ direction = "l" }))
hl.bind(mod .. " + SHIFT + Down",  hl.dsp.window.move({ direction = "d" }))
hl.bind(mod .. " + SHIFT + Up",    hl.dsp.window.move({ direction = "u" }))
hl.bind(mod .. " + SHIFT + Right", hl.dsp.window.move({ direction = "r" }))

-- ── Splits / layout ───────────────────────────────────────────────────────────
-- i3 "split h/v" → dwindle preselect for the next window.
hl.bind(mod .. " + b", hl.dsp.layout("preselect r"))
hl.bind(mod .. " + v", hl.dsp.layout("preselect d"))

hl.bind(mod .. " + f", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
-- Preserve all tiled splits while using the full output: hide the bar and
-- release its exclusive screen space without changing window state.
hl.bind(mod .. " + SHIFT + f", hl.dsp.exec_cmd("qs ipc call bar toggle"))

-- i3 stacking/tabbed layouts → Hyprland groups (a group renders as tabs).
-- $mod+w and $mod+s both toggle the group (Hyprland has no separate stacked
-- mode); $mod+e leaves/toggles the split, as in i3.
hl.bind(mod .. " + w", hl.dsp.group.toggle())
hl.bind(mod .. " + s", hl.dsp.group.toggle())
hl.bind(mod .. " + e", hl.dsp.layout("togglesplit"))
-- Cycle tabs inside a group with focus keys crossing group edges.
hl.bind(mod .. " + g", hl.dsp.group.next())

-- Toggle tiling / floating
hl.bind(mod .. " + SHIFT + space", hl.dsp.window.float({ action = "toggle" }))
-- i3's "focus mode_toggle" (jump between tiling and floating layers) has no
-- exact Hyprland dispatcher; cyclenext floating focuses the floating layer,
-- directional focus ($mod+h/j/k/l) crosses back.
hl.bind(mod .. " + space", hl.dsp.window.cycle_next({ next = true, floating = true }))

-- i3 "focus parent" has no Hyprland equivalent (no container tree).

-- Drag windows with $mod + mouse (i3 floating_modifier / tiling_drag)
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize())

-- ── Workspaces ────────────────────────────────────────────────────────────────
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    -- move focused container to workspace (i3 default: don't follow)
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

-- ── Reload / exit ─────────────────────────────────────────────────────────────
-- Hyprland reloads config live; both i3 "reload" and "restart" map to it.
hl.bind(mod .. " + SHIFT + c", hl.dsp.exec_cmd("hyprctl reload && notify-send \"Hyprland\" \"Config reloaded\""))
hl.bind(mod .. " + SHIFT + r", hl.dsp.exec_cmd("hyprctl reload && notify-send \"Hyprland\" \"Config reloaded\""))
hl.bind(mod .. " + SHIFT + e", hl.dsp.exec_cmd(
    "bash -c '[ \"$(printf \"No\\nYes\" | rofi -dmenu -p \"Exit Hyprland?\")\" = \"Yes\" ] && hyprctl dispatch \"hl.dsp.exit()\"'"
))

-- ── Resize mode (i3 mode "resize" → Hyprland submap) ─────────────────────────
hl.bind(mod .. " + r", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    hl.bind("h", hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
    hl.bind("j", hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })
    hl.bind("k", hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
    hl.bind("l", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
    hl.bind("Left",  hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
    hl.bind("Down",  hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })
    hl.bind("Up",    hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
    hl.bind("Right", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
    hl.bind("Return", hl.dsp.submap("reset"))
    hl.bind("Escape", hl.dsp.submap("reset"))
    hl.bind(mod .. " + r", hl.dsp.submap("reset"))
end)

-- ── Look & feel ───────────────────────────────────────────────────────────────
hl.config({
    -- Gaps match i3 (inner 10, outer 4 → Hyprland gaps_in is per-side).
    general = {
        gaps_in = 5,
        gaps_out = 14,
        border_size = 1,
        -- Muted pastel blue remains visible against virtually any dark surface.
        col = {
            active_border = "rgba(8a9199cc)",
            inactive_border = "rgba(30344299)",
        },
        layout = "dwindle",
        resize_on_border = true,
    },

    dwindle = {
        preserve_split = true,
        -- 0 (default) splits toward the mouse position; 2 = new window always
        -- opens right/bottom, like i3.
        force_split = 2,
    },

    group = {
        col = {
            border_active = "rgba(8a9199cc)",
            border_inactive = "rgba(30344299)",
        },
        groupbar = {
            font_family = "Inter",
            font_size = 11,
            col = {
                active = "rgb(7fb99a)",
                inactive = "rgb(1d202b)",
            },
            text_color = "rgb(ececf1)",
        },
    },

    -- Light glass treatment applies compositor-wide, including clients that
    -- do not expose their own transparency setting.
    decoration = {
        rounding = 14,
        active_opacity = 0.80,
        inactive_opacity = 0.70,
        fullscreen_opacity = 1.0,
        blur = {
            enabled = true,
            size = 8,
            -- Each pass is a full-screen sample of a 2560x1600 buffer, and this
            -- is a Wildcat Lake iGPU sharing system memory. The third pass costs
            -- a full pass worth of bandwidth to widen an already 8px radius by an
            -- amount that is not visible at this size; two passes look the same
            -- and leave more headroom for everything compositing on top.
            passes = 2,
            ignore_opacity = true,
            new_optimizations = true,
        },
        -- macOS-style focus model paired with the subtle gray active border:
        -- unfocused windows dim slightly, so focus reads as "the bright window".
        dim_inactive = true,
        dim_strength = 0.12,
        shadow = {
            enabled = true,
        },
        -- Off: it samples the framebuffer again on every frame of a move or
        -- resize, which is exactly when the compositor is already busiest, and
        -- the trail it buys is barely visible on an iGPU that cannot keep the
        -- frame rate up while drawing it.
        motion_blur = {
            enabled = false,
        },
    },

    animations = {
        enabled = true,
    },

    misc = {
        font_family = "Inter",
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },

    -- Fullscreen surfaces scan out straight to the display, skipping the composite
    -- pass entirely (video, games). No effect on tiled/windowed rendering.
    render = {
        direct_scanout = true,
    },

    -- Crisp XWayland apps under fractional scale.
    xwayland = {
        force_zero_scaling = true,
    },
})

-- ── Behavior ──────────────────────────────────────────────────────────────────
hl.config({
    -- Jump back to previous workspace on repeated press.
    binds = {
        workspace_back_and_forth = true,
    },
})

-- decoration.active_opacity multiplies the client's own alpha, so the 0.80
-- glass that suits every other window would drag Ghostty's 0.92 down to 0.74
-- and let the wallpaper back in. Exempt it; its own alpha is the only one.
hl.window_rule({
    name = "ghostty-opacity",
    match = { class = "com.mitchellh.ghostty" },
    opacity = "1.0 1.0",
})

-- Blur the wallpaper behind Quickshell's translucent island while ignoring the
-- fully transparent remainder of its full-width layer surface.
hl.layer_rule({
    name = "quickshell-bar-blur",
    match = { namespace = "quickshell-bar" },
    blur = true,
    ignore_alpha = 0.20,
})

hl.curve("easeOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
-- speed is in deciseconds, so 3 was 300ms added to every window open on top of
-- the ~670ms Ghostty itself takes to start. 2 still reads as a deliberate popin
-- rather than a jump, and returns 100ms of that.
hl.animation({ leaf = "windows",    enabled = true, speed = 2, bezier = "easeOut", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "easeOut", style = "popin 90%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "layersIn",   enabled = true, speed = 2, bezier = "easeOut", style = "popin 90%" })
hl.animation({ leaf = "layersOut",  enabled = true, speed = 2, bezier = "easeOut", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "easeOut", style = "slide" })

-- Keep this line verbatim and unprotected: hyprmoncfg checks after every reload that
-- its rules actually ran and re-appends this exact form if they did not, so a pcall()
-- wrapper here just earns a duplicate. The target is generated and gitignored, so
-- linux/setup.sh seeds a stub on fresh bootstraps to keep dofile() from throwing.

-- Added by hyprmoncfg: its generated monitor rules load last, so nothing before this can override the applied layout.
dofile(os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua")
