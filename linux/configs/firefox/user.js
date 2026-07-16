// Firefox prefs for Ubuntu 26.04 / Wayland (native). Kept deliberately
// minimal: Firefox 152+ already enables WebRender and GPU acceleration where
// the driver stack is safe — never force-enable compositor/decode paths here
// (the old X11-era force flags caused visual glitching under Wayland).

// Enable userChrome.css and userContent.css
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Built-in dark theme (a fresh profile defaults to "system auto", which can
// resolve light under Hyprland where no desktop color-scheme is set).
user_pref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");

// Compact UI density
user_pref("browser.uidensity", 1);
user_pref("browser.compactmode.show", true);

// Typography: Ubuntu Sans gives Firefox a crisp, contemporary proportional
// interface and is shipped with Ubuntu. Keep Fira Code for source and terminal
// content, where a monospaced face is actually useful.
user_pref("font.default.x-western", "sans-serif");
user_pref("font.name.sans-serif.x-western", "Ubuntu Sans");
user_pref("font.name.serif.x-western", "Noto Serif");
user_pref("font.name.monospace.x-western", "FiraCode Nerd Font Mono");
user_pref("font.size.variable.x-western", 17);
user_pref("font.size.monospace.x-western", 14);
user_pref("font.minimum-size.x-western", 0);

// Use one global full-page zoom level rather than saving a different value for
// every site. The profile setup seeds its content preference to 125%.
user_pref("browser.zoom.full", true);
user_pref("browser.zoom.siteSpecific", false);

// Dark preference for sites that honor prefers-color-scheme
user_pref("layout.css.prefers-color-scheme.content-override", 0);

// VA-API hardware video decoding: opt in, but let Firefox decide per-codec —
// no force-enabled override.
user_pref("media.ffmpeg.vaapi.enabled", true);

// Smooth scrolling: shorter animation + spring physics for a fluid feel
user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.msdPhysics.enabled", true);
user_pref("general.smoothScroll.mouseWheel.durationMinMS", 100);
user_pref("general.smoothScroll.mouseWheel.durationMaxMS", 200);
user_pref("general.smoothScroll.lines.durationMinMS", 125);
user_pref("general.smoothScroll.lines.durationMaxMS", 125);

// Fewer session-store disk writes (default 15000ms)
user_pref("browser.sessionstore.interval", 30000);

// Blank homepage and blank new tabs (skips the widget/wallpaper newtab)
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.newtabpage.enabled", false);

// No pocket / sponsored / first-run noise
user_pref("extensions.pocket.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
