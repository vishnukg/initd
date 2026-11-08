// The managed Firefox prefs; the default page zoom is separate (it lives in
// content-prefs.sqlite, see linux/scripts/firefox-profile.mjs:setDefaultZoom).
// Linked into the active profile by `firefox-profile.mjs setup`; read at
// startup, so it needs a Firefox restart.
//
// Toolbar text size is NOT set here: ui.textScaleFactor scales the toolbar's
// boxes and icons but barely its text (measured on 159: 100 -> 160 left
// "example.org" in the address bar almost unchanged), and the ui.font.*.size
// prefs have no effect at all. chrome/userChrome.css sets the font size
// directly instead, and pages are sized by the default zoom alone.
// Pinned at its default of 100 rather than omitted: an earlier user.js set it
// to 115 and then 130, and dropping a line never resets a pref Firefox has
// already saved to prefs.js.
user_pref("ui.textScaleFactor", 100);

// Normal UI density (0 normal, 1 compact): compact capped the address bar and
// tabs at a height that left the 18px toolbar text looking cramped and small,
// so the toolbar now gets normal density's taller rows and padding. Pinned
// rather than omitted, since an earlier user.js set it to 1. compactmode.show
// keeps "Compact" offered in Customize Toolbar → Density to switch back by hand.
user_pref("browser.uidensity", 0);
user_pref("browser.compactmode.show", true);

// Load chrome/userChrome.css, which hides Firefox's own minimise/maximise/close
// buttons so Hyprland's border and rounding are the only window decoration,
// and sets the toolbar's font size.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
