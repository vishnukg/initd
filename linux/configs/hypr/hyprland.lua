-- Hyprland config — originally a direct port of this repo's old i3 config
-- (linux/configs/i3/, removed with the rest of the X11 stack; git history has
-- it), then ported from hyprlang (hyprland.conf) to Lua ahead of hyprlang's
-- removal in Hyprland 0.57. The core keybindings (focus, move, workspaces,
-- splits, resize mode) still follow that i3 config, with comments where a
-- concept has no exact Hyprland equivalent; the rest (Ghostty, the Copilot
-- key, Ctrl+Super+Q lock, bar toggle) were added since. Hyprland picks
-- .lua vs .conf at STARTUP only, never on `hyprctl reload` — validate edits
-- with `Hyprland --verify-config --config <path>` instead of restarting.
-- Reference: https://wiki.hypr.land/Configuring/

local mod = "SUPER"

-- GDM does not start fish, so its PATH has no mise shims. Session helpers
-- written in Node must resolve just as they do from an interactive shell.
local home = os.getenv("HOME")
hl.env("PATH", home .. "/.local/share/mise/shims:" .. home .. "/.local/bin:" .. (os.getenv("PATH") or "/usr/bin:/bin"))

-- Breeze (KDE's cursor; breeze-cursor-theme in packages.txt) when installed,
-- otherwise Adwaita, which every Fedora has -- a missing package must never
-- leave the session with no cursor. linux/setup.sh makes the same choice for
-- GTK's gsetting, and ~/.icons/default inherits Breeze then Adwaita.
local cursor_theme = "Adwaita"
do
    local probe = io.open("/usr/share/icons/breeze_cursors/index.theme", "r")
    if probe then
        probe:close()
        cursor_theme = "breeze_cursors"
    end
end
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", cursor_theme)

-- Qt apps (EasyEffects, Media Writer) follow the GTK theme the way Omarchy 4
-- does it: Qt's own gtk3 platform theme (libqgtk3.so, shipped in
-- qt6-qtbase-gui) hands Fusion the GTK palette, so Qt windows go dark with
-- everything else and track any later GTK theme change. No Kvantum and no
-- QT_STYLE_OVERRIDE: Omarchy dropped both, since Kvantum never followed the
-- GTK theme. Wayland first, XWayland as the fallback.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")

-- No accessibility bus: every GTK app otherwise starts at-spi-bus-launcher and
-- at-spi2-registryd (~15 MB, two processes) and pays the bridge setup at
-- launch. Nothing here uses a screen reader; drop these two lines if one is
-- ever needed. GTK4 reads GTK_A11Y, GTK3/ATK reads NO_AT_BRIDGE. Exported to
-- D-Bus/systemd activation too (session_vars), so the portals and anything
-- else activated that way skip it as well.
hl.env("GTK_A11Y", "none")
hl.env("NO_AT_BRIDGE", "1")

-- No realtime scheduling for the compositor. Since 0.57, Hyprland asks rtkit
-- for SCHED_RR and in exchange accepts RLIMIT_RTTIME at rtkit's
-- RTTimeUSecMax: 150 ms soft / 200 ms hard of CPU without blocking. Hotplugging
-- the Dell U2725QE (4K@120 over USB-C) overran it: the kernel SIGKILLed
-- Hyprland in the middle of bringing the output up, so there was no core and no
-- crash report, and start-hyprland restarted it in safe mode. The SIGXCPU
-- handler at the soft limit never ran ("Realtime budget exceeded" was never
-- logged), so the time was spent where a signal cannot land. Startup with the
-- monitor already attached survived only because realtime is requested after
-- the first modeset. Hyprland reads this once at startup, after the config is
-- parsed, so it takes effect from the next login; it restores 0.56's normal
-- scheduling.
hl.env("HYPRLAND_NO_RT", "1")

-- ── Monitors ──────────────────────────────────────────────────────────────────
-- Wayland replaces the whole autorandr/xsettingsd/Xft.dpi machinery with
-- per-monitor scale. 1.33333 on the laptop panel (2560x1600, ~224 PPI) — a
-- 1920x1200 logical workspace; adjust per monitor if needed. This was 1.5
-- (tuned for the old machine's panel), then 1.25, which read a touch small.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = "1.33333" })
hl.monitor({ output = "",      mode = "preferred", position = "auto", scale = "1.33333" })

-- ── Input ─────────────────────────────────────────────────────────────────────
hl.config({
    input = {
        -- setxkbmap -option ctrl:nocaps
        kb_options = "ctrl:nocaps",
        -- Start repeating after 350 ms, at 30 repeats per second.
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
-- Everything below is started explicitly because XDG autostart never fires
-- here: initd-hyprland-session.service does bring up graphical-session.target,
-- but xdg-desktop-autostart.target is started by the session manager (GNOME
-- does, Hyprland doesn't), so nm-applet's, blueman's and 1Password's
-- /etc/xdg/autostart entries would otherwise be skipped.
local session_vars = "WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME XCURSOR_THEME XCURSOR_SIZE GTK_A11Y NO_AT_BRIDGE"
hl.on("hyprland.start", function()
    -- Make portals (screenshare, file pickers) and D-Bus- or systemd-started
    -- apps see the session environment (the QT_QPA_* pair included, so a
    -- Qt app started that way still follows the GTK theme), then reach
    -- graphical-session.target and (re)start hyprmoncfgd and Quickshell under
    -- it. Quickshell (the bar) is a unit so a crash restarts it in a second
    -- (initd-quickshell.service); restarted rather than just started so a
    -- second login never keeps a bar holding the previous session's env.
    hl.exec_cmd("sh -c '"
        .. "dbus-update-activation-environment --systemd " .. session_vars
        .. " && systemctl --user import-environment " .. session_vars
        .. " && systemctl --user start initd-hyprland-session.service"
        .. " && systemctl --user restart hyprmoncfgd.service"
        .. " && systemctl --user restart initd-quickshell.service'")

    -- Polkit auth agent (GNOME ships its own inside gnome-shell; Hyprland needs
    -- one): the password prompt for pkexec, 1Password's system unlock and the
    -- like. mate-polkit is GTK3, so it gets adw-gtk3-dark; lxpolkit was GTK2
    -- and drew in the old default look. Its XDG autostart entry is MATE-only.
    hl.exec_cmd("/usr/libexec/polkit-mate-authentication-agent-1")

    hl.exec_cmd("hypridle")
    -- The wallpaper link (and the theme files) must exist before hyprpaper
    -- reads hyprpaper.conf; `ensure` is a no-op when they do.
    hl.exec_cmd("sh -c 'node ~/.config/wallpaper.mjs ensure; exec hyprpaper'")
    hl.exec_cmd("nm-applet")
    -- blueman-applet runs headless (linux/setup.sh disables its StatusIcon
    -- plugin): the bar draws Bluetooth itself, and the applet stays only as
    -- BlueZ's pairing agent and OBEX receiver.
    hl.exec_cmd("blueman-applet")
    -- 1Password is autostarted because its SSH agent serves the GitHub and
    -- exe.dev keys (~/.ssh/config): without it running and unlocked, git
    -- push/pull and Ghostty's dev box windows fail with "Permission denied
    -- (publickey)". The cost is ~645 MB idle across three Electron processes
    -- on a 16 GB machine. No startup delay: the bar places tray icons by role
    -- (nm-applet, native Bluetooth, then the rest), so registration order no
    -- longer decides where its icon lands.
    hl.exec_cmd("1password --silent")
end)

-- ── Media / hardware keys ─────────────────────────────────────────────────────
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"),   { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"),  { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("bash -c 'brightnessctl --min-val=2 -q set 5%- && qs ipc --any-display call bar refreshBrightness'"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("bash -c 'brightnessctl -q set 5%+ && qs ipc --any-display call bar refreshBrightness'"),             { locked = true, repeating = true })

-- Screenshots land in ~/Pictures/Screenshots; region also copies to the clipboard.
-- linux/scripts/screenshot.mjs, linked by linux/scripts/config-links.mjs.
hl.bind("Print",                hl.dsp.exec_cmd("~/.config/screenshot.mjs full"))
hl.bind(mod .. " + SHIFT + s",  hl.dsp.exec_cmd("~/.config/screenshot.mjs region"))

-- ── Apps ──────────────────────────────────────────────────────────────────────
-- kitty is the default, local terminal; Ghostty (SUPER+t below) is the dev box
-- terminal on personal machines. kitty as the default is a memory decision,
-- not a taste one: Ghostty 1.3.1 leaks on window *lifecycle* (upstream #9433 /
-- #9786 / #10244 / #10269) — 69 → 204 MB across ~5 open/close cycles, held with zero
-- windows open, ~1 GB over a day of real use. kitty's fresh window peaked at
-- 162 MB on the same payload and gave all of it back on exit. Cold start
-- agrees: kitty ~223ms against Ghostty's ~680ms, which no Ghostty config knob
-- moves.
--
-- NEITHER is launched single-instance (`kitty --single-instance` /
-- `ghostty --gtk-single-instance`), and no Ghostty server is enabled. One
-- process owning every window is exactly what turns that leak into a
-- session-wide problem; separate processes hand the memory back on close.
--
-- No opacity flags on either: Linux's 0.92 is a tracked per-OS config file
-- (kitty's linux.conf via `include ${KITTY_OS}.conf`; Ghostty's via the
-- linux.conf link linux/setup.sh places next to the shared config), so every
-- launcher agrees — these binds, rofi, .desktop entries, docker-menu.mjs. A
-- flag would only reach windows opened by that one keybind and leave the rest
-- at the shared config's macOS value (0.58 for both terminals).
hl.bind(mod .. " + Return", hl.dsp.exec_cmd("kitty"))
hl.bind(mod .. " + t", hl.dsp.exec_cmd("ghostty"))
-- The browser follows the system default (xdg-settings, set to Chrome by
-- linux/scripts/chrome-profile.mjs) instead of naming one here, and launches
-- through its .desktop entry so it gets the same flags as rofi and xdg-open
-- links — for Chrome, the 120% scaling in the shadowed launcher. Both Chrome
-- and Firefox open a new window when already running.
hl.bind(mod .. " + SHIFT + Return", hl.dsp.exec_cmd([[sh -c 'gtk-launch "$(xdg-settings get default-web-browser)"']]))
hl.bind(mod .. " + SHIFT + q", hl.dsp.window.close())
hl.bind(mod .. " + d",   hl.dsp.exec_cmd("rofi -show drun"))
hl.bind(mod .. " + Tab", hl.dsp.exec_cmd("rofi -show window"))
-- Keyboard's dedicated "Copilot" key: the kernel has no keycode for it, so
-- the firmware sends a synthetic Super+Shift+F23 chord instead (confirmed
-- via `libinput debug-events`). Wired to the same app launcher as mod+d.
hl.bind(mod .. " + SHIFT + F23", hl.dsp.exec_cmd("rofi -show drun"))
-- Toggle night light (4500 K via night-light.service; a schedule keeps it on
-- 19:00–07:00, and this manual toggle stands until the next boundary)
hl.bind(mod .. " + SHIFT + n", hl.dsp.exec_cmd("~/.config/night-light-toggle.mjs"))

-- Lock now / lock-session (hypridle runs hyprlock on loginctl lock-session)
-- Ctrl+Super+Q mirrors macOS's Ctrl+Cmd+Q; $mod+Shift+X kept as the original.
hl.bind(mod .. " + CTRL + q",  hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mod .. " + SHIFT + x", hl.dsp.exec_cmd("loginctl lock-session"))

-- ── Focus / move (i3 vim keys + arrows) ──────────────────────────────────────
-- One table drives focus, move and the resize submap below. Each direction is
-- reachable by its vim key and its arrow key.
local directions = {
    { keys = { "h", "Left" },  dir = "l", dx = -40, dy = 0 },
    { keys = { "j", "Down" },  dir = "d", dx = 0,   dy = 40 },
    { keys = { "k", "Up" },    dir = "u", dx = 0,   dy = -40 },
    { keys = { "l", "Right" }, dir = "r", dx = 40,  dy = 0 },
}
for _, d in ipairs(directions) do
    for _, key in ipairs(d.keys) do
        hl.bind(mod .. " + " .. key,           hl.dsp.focus({ direction = d.dir }))
        hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = d.dir }))
    end
end

-- ── Splits / layout ───────────────────────────────────────────────────────────
-- i3 "split h/v" → dwindle preselect for the next window.
hl.bind(mod .. " + b", hl.dsp.layout("preselect r"))
hl.bind(mod .. " + v", hl.dsp.layout("preselect d"))

hl.bind(mod .. " + f", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
-- Preserve all tiled splits while using the full output: hide the bar and
-- release its exclusive screen space without changing window state.
-- Every `qs ipc` here passes --any-display: Quickshell records its display as
-- "unk" however it is launched, so without it the call matches no instance and
-- silently does nothing. This machine only ever runs one session.
hl.bind(mod .. " + SHIFT + f", hl.dsp.exec_cmd("qs ipc --any-display call bar toggle"))
-- Quick settings: toggles, sliders, media, power and notification history.
-- Wallpapers: the picker, and the next one in the current collection. Each
-- re-themes the desktop from the new wallpaper (linux/scripts/theme.mjs).
hl.bind(mod .. " + SHIFT + w", hl.dsp.exec_cmd("node ~/.config/wallpaper.mjs pick"))
hl.bind(mod .. " + CTRL + w",  hl.dsp.exec_cmd("node ~/.config/wallpaper.mjs next"))
hl.bind(mod .. " + a", hl.dsp.exec_cmd("qs ipc --any-display call bar togglePanel"))
-- Workspace overview: every workspace with still previews of its windows.
hl.bind(mod .. " + o", hl.dsp.exec_cmd("qs ipc --any-display call bar toggleOverview"))

-- i3 stacking/tabbed layouts → Hyprland groups (a group renders as tabs).
-- $mod+w and $mod+s both toggle the group (Hyprland has no separate stacked
-- mode); $mod+e leaves/toggles the split, as in i3.
hl.bind(mod .. " + w", hl.dsp.group.toggle())
hl.bind(mod .. " + s", hl.dsp.group.toggle())
hl.bind(mod .. " + e", hl.dsp.layout("togglesplit"))
-- Cycle to the next tab inside the focused group.
hl.bind(mod .. " + g", hl.dsp.group.next())

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
-- Hyprland reloads config live, monitor rules included, so i3's "reload",
-- "restart" and "re-apply layout" keys collapsed into this one. hyprmoncfgd
-- handles hotplug and lid events on its own.
hl.bind(mod .. " + SHIFT + c", hl.dsp.exec_cmd("hyprctl reload && notify-send \"Hyprland\" \"Config reloaded\""))
hl.bind(mod .. " + SHIFT + e", hl.dsp.exec_cmd(
    "bash -c '[ \"$(printf \"No\\nYes\" | rofi -dmenu -p \"Exit Hyprland?\")\" = \"Yes\" ] && hyprctl dispatch \"hl.dsp.exit()\"'"
))

-- ── Resize mode (i3 mode "resize" → Hyprland submap) ─────────────────────────
hl.bind(mod .. " + r", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    for _, d in ipairs(directions) do
        for _, key in ipairs(d.keys) do
            hl.bind(key, hl.dsp.window.resize({ x = d.dx, y = d.dy, relative = true }), { repeating = true })
        end
    end
    hl.bind("Return", hl.dsp.submap("reset"))
    hl.bind("Escape", hl.dsp.submap("reset"))
    hl.bind(mod .. " + r", hl.dsp.submap("reset"))
end)

-- ── Look & feel ───────────────────────────────────────────────────────────────
hl.config({
    -- gaps_in is per-side, so 5 gives i3's 10px between windows; the outer gap
    -- grew from i3's 4 to 14 to let the rounded corners and blur breathe.
    general = {
        gaps_in = 5,
        gaps_out = 14,
        -- No border: windows are separated by the gaps, rounding and the soft
        -- shadow, and focus is carried by dim_inactive, the opacity split and the
        -- active-window shadow. The colours below are kept for the day a border
        -- comes back (they would draw as an ~8% white hairline); at size 0
        -- nothing draws them. resize_on_border still works: Hyprland's grab
        -- area extends past the window edge.
        border_size = 0,
        col = {
            active_border = "rgba(ffffff14)",
            inactive_border = "rgba(ffffff0a)",
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
            border_active = "rgba(ffffff14)",
            border_inactive = "rgba(ffffff0a)",
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
        active_opacity = 0.96,
        inactive_opacity = 0.90,
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
            -- Floating windows (dialogs, popups) blur the cached wallpaper instead
            -- of re-sampling the tiled windows under them every frame — the same
            -- cache tiled windows already use. Tiled windows sit on the wallpaper
            -- anyway, so only overlapping floats look different.
            xray = true,
        },
        -- macOS-style focus model: unfocused windows dim slightly, so focus
        -- reads as "the bright window", lifted by the only full shadow.
        dim_inactive = true,
        -- 0.20 rather than 0.12: with no border, dimming is the main focus cue,
        -- so it has to be obvious at a glance.
        dim_strength = 0.20,
        -- A wide, soft drop shadow lifts windows off the wallpaper instead of a
        -- border outlining them. Full strength on the focused window only:
        -- inactive ones get a faint one, which is both a second focus cue and
        -- less shadow area to blend per frame on this iGPU.
        shadow = {
            enabled = true,
            range = 20,
            render_power = 3,
            color = "rgba(00000066)",
            color_inactive = "rgba(00000022)",
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
        -- Let a new hyprlock take over a session whose lock client died or
        -- lost its surfaces (an output vanishing mid-lock, as the external
        -- monitor's USB-C link does on resume). Without it the only way out
        -- of a stuck lock is logging out. The session stays locked either way:
        -- this only permits another lock client to claim it. Recovery from a
        -- TTY is in docs/linux-monitors.md.
        allow_session_lock_restore = true,
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

    -- Jump back to previous workspace on repeated press.
    binds = {
        workspace_back_and_forth = true,
    },
})

-- ── Window and layer rules ────────────────────────────────────────────────────
-- Rule opacity multiplies decoration.active/inactive_opacity unless each value
-- carries `override`, and both multiply the client's own background alpha.

-- Exempt Ghostty from the global glass: its own 0.92 (linux.conf) is the only
-- alpha, so the dev box terminal stays readable over a bright wallpaper.
hl.window_rule({
    name = "ghostty-opacity",
    match = { class = "com.mitchellh.ghostty" },
    opacity = "1.0 override 1.0 override",
})

-- kitty: 0.80 focused, 0.70 unfocused, opaque fullscreen, on top of its own
-- 0.92 background alpha (linux.conf).
hl.window_rule({
    name = "kitty-opacity",
    match = { class = "kitty" },
    opacity = "0.80 override 0.70 override 1.0 override",
})

-- Blur the wallpaper behind Quickshell's translucent island while ignoring the
-- fully transparent remainder of its full-width layer surface.
hl.layer_rule({
    name = "quickshell-bar-blur",
    match = { namespace = "quickshell-bar" },
    blur = true,
    ignore_alpha = 0.20,
})

-- The same frosted glass for Quickshell's transient surfaces: the volume and
-- brightness indicator, notification banners, the quick settings panel. Each
-- exists only while shown, so the blur costs nothing the rest of the time.
-- The launcher (rofi): same frosted card. ignore_alpha keeps the blur to the
-- card itself, not the transparent margin around it.
hl.layer_rule({
    name = "rofi-blur",
    match = { namespace = "^rofi$" },
    blur = true,
    ignore_alpha = 0.20,
})

hl.layer_rule({
    name = "quickshell-overlay-blur",
    match = { namespace = "^quickshell-(osd|notifications|panel|overview)$" },
    blur = true,
    ignore_alpha = 0.20,
})

hl.curve("easeOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
-- speed is in deciseconds, and this one is pure perceived latency: it is painted
-- on top of the time the terminal takes to map a window (~223ms for kitty, the
-- default; ~680ms for Ghostty, and no Ghostty config knob moves that number).
-- The animation is the part that is actually ours to spend. 3 cost 300ms, 2 cost
-- 200ms, 1 costs 100ms and still reads as a popin rather than a jump. windowsOut
-- stays at 2 — closing is not a wait.
hl.animation({ leaf = "windows",    enabled = true, speed = 1, bezier = "easeOut", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "easeOut", style = "popin 90%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "layersIn",   enabled = true, speed = 2, bezier = "easeOut", style = "popin 90%" })
hl.animation({ leaf = "layersOut",  enabled = true, speed = 2, bezier = "easeOut", style = "fade" })
-- slidefade 20%: the new workspace slides a fifth of the width while fading
-- in, rather than a whole screen; direction still reads, at less motion.
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "easeOut", style = "slidefade 20%" })

-- Each Quickshell surface enters from where it lives: banners from the right
-- edge, quick settings and the volume/brightness pill down from
-- the bar. (The launcher keeps the layersIn popin.) Same layersIn timing.
hl.layer_rule({ name = "notifications-slide", match = { namespace = "^quickshell-notifications$" }, animation = "slide right" })
hl.layer_rule({ name = "panel-slide",         match = { namespace = "^quickshell-panel$" },         animation = "slide top" })
hl.layer_rule({ name = "osd-slide",           match = { namespace = "^quickshell-osd$" },           animation = "slide top" })

-- Keep the loader line below verbatim: hyprmoncfg (1.17+) owns it, checks after every
-- reload that its rules actually ran, and rewrites it in this exact form if not. It is
-- guarded, so a fresh bootstrap with no generated file yet simply keeps the static
-- hl.monitor() fallbacks above until the first profile is applied.

-- Added by hyprmoncfg: its generated monitor rules load last, so nothing before this can override the applied layout.
do local path = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"; local file = io.open(path, "r"); if file then file:close(); dofile(path) end end
