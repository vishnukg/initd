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
