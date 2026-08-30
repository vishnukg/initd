// Native-window integration for Hyprland + media tuning.
// Applied by linux/setup.sh:link_firefox_profile via a symlink into the
// active profile. Requires a Firefox restart to take effect.
// (Default zoom is a separate mechanism — see set_firefox_default_zoom below.)

// Required or Firefox ignores chrome/userChrome.css entirely.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Merge the titlebar into the tab strip — Hyprland doesn't draw its own
// titlebars, so a separate Firefox titlebar just wastes vertical space and
// looks like a foreign X11-era app.
user_pref("browser.tabs.inTitlebar", 1);

// Round the GTK CSD window corners on Wayland, matching Hyprland's
// decoration.rounding = 12 in hyprland.conf.
user_pref("widget.gtk.rounded-bottom-corners.enabled", true);

// Use Firefox's normal density so toolbar controls have comfortable spacing.
user_pref("browser.uidensity", 0);
user_pref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");

// Ubuntu Sans was supplied by Mint. Fedora does not package it in the enabled
// repositories, so Adwaita Sans is the installed proportional fallback; the
// original FiraCode Nerd Font Mono is available locally.
user_pref("font.default.x-western", "sans-serif");
user_pref("font.name.sans-serif.x-western", "Adwaita Sans");
user_pref("font.name.serif.x-western", "Noto Serif");
user_pref("font.name.monospace.x-western", "FiraCode Nerd Font Mono");
user_pref("font.size.variable.x-western", 17);
user_pref("font.size.monospace.x-western", 14);
user_pref("font.minimum-size.x-western", 0);

user_pref("browser.theme.content-theme", 2);
user_pref("browser.display.background_color.dark", "#0b0c12");
user_pref("layout.css.prefers-color-scheme.content-override", 0);
user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.msdPhysics.enabled", true);

// Default page zoom (133%) is set separately in content-prefs.sqlite by
// linux/setup.sh:set_firefox_default_zoom — that's the mechanism Firefox's
// own Zoom UI actually reads; a pref here can't drive it.

// Hardware video decode via the libva-intel-media-driver installed in
// packages.txt. force-enabled bypasses Mozilla's hardware allowlist, which
// is unlikely to already recognize this machine's iGPU.
user_pref("media.hardware-video-decoding.force-enabled", true);

// ── Memory ───────────────────────────────────────────────────────────────────
// This machine has 16 GB soldered and Firefox is its largest consumer (~2.3 GB
// across the parent, content, WebExtensions and RDD processes). Both prefs
// trade a little responsiveness for resident memory.

// Content process cap, left at Firefox's default of 8 — set explicitly rather
// than omitted, because removing a line from user.js does NOT reset the pref:
// prefs.js keeps the last value written, so a stale override would survive.
//
// Dropping this to 4 was tried and reverted. Two reasons it wasn't worth it:
// Fission (site isolation, default-on) splits content across two pools, and
// this pref only caps the shared non-isolated one — per-site processes are
// governed by dom.ipc.processCount.webIsolated instead — so it reached maybe
// 100 MB. And the smaller pool cost noticeable startup parallelism, since
// restoring tabs queues them through fewer slots. The parent process (~530 MB)
// and the WebExtensions process (~327 MB) are the real consumers here, and
// neither is affected by this setting at all.
user_pref("dom.ipc.processCount", 8);

// Back/forward cache — pages held fully alive in memory for instant Back.
// Default scales with RAM (up to 8). Three keeps Back snappy for recent pages
// while dropping the long tail that only costs memory.
user_pref("browser.sessionhistory.max_total_viewers", 3);
