// The managed Firefox prefs; the default page zoom is separate (it lives in
// content-prefs.sqlite, see linux/scripts/firefox-profile.mjs:setDefaultZoom).
// Linked into the active profile by `firefox-profile.mjs setup`; read at
// startup, so it needs a Firefox restart.
//
// Text size, in percent, for the whole browser: tabs, toolbar, menus, settings
// pages and web pages alike. Relative to the monitor's own scale, so it stays
// right when a window moves between the 1.33x panel and an external monitor —
// unlike layout.css.devPixelsPerPx, which is one absolute ratio for every
// output. Removing this line later does NOT reset it: Firefox has copied it
// into prefs.js, so reset it in about:config too.
user_pref("ui.textScaleFactor", 115);

// Compact UI density (0 normal, 1 compact). compactmode.show keeps "Compact"
// offered in Customize Toolbar → Density, which Firefox otherwise hides.
user_pref("browser.uidensity", 1);
user_pref("browser.compactmode.show", true);

// Load chrome/userChrome.css, which hides Firefox's own minimise/maximise/close
// buttons so Hyprland's border and rounding are the only window decoration.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
