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

// Compact UI density (less padding — more screen real estate for tiling)
// and Firefox's own built-in dark theme, matching the rest of the desktop.
user_pref("browser.uidensity", 1);
user_pref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");

// Default page zoom (125%) is set separately in content-prefs.sqlite by
// linux/setup.sh:set_firefox_default_zoom — that's the mechanism Firefox's
// own Zoom UI actually reads; a pref here can't drive it.

// Hardware video decode via the libva-intel-media-driver installed in
// packages.txt. force-enabled bypasses Mozilla's hardware allowlist, which
// is unlikely to already recognize this machine's iGPU.
user_pref("media.hardware-video-decoding.force-enabled", true);
