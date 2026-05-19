// Enable userChrome.css and userContent.css
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Compact UI density
user_pref("browser.uidensity", 1);
user_pref("browser.compactmode.show", true);

// Smooth scrolling
user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.lines.durationMaxMS", 125);
user_pref("general.smoothScroll.lines.durationMinMS", 125);
user_pref("general.smoothScroll.mouseWheel.durationMaxMS", 200);
user_pref("general.smoothScroll.mouseWheel.durationMinMS", 100);

// Prefer dark color scheme for sites that respect it
user_pref("layout.css.prefers-color-scheme.content-override", 0);

// Better font rendering
user_pref("gfx.text.subpixel-antialiasing.enabled", true);

// Remove pocket, screenshots, etc from toolbar defaults
user_pref("extensions.pocket.enabled", false);

// Force WebRender GPU compositor (fixes slow rendering on complex pages like YouTube)
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.compositor.force-enabled", true);

// VA-API hardware video decoding (Intel Arc)
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);
user_pref("media.av1.enabled", true);

// HTTP/3 (QUIC) — faster connections where supported
user_pref("network.http.http3.enabled", true);

// More parallel connections (default is 6/server, 256 total)
user_pref("network.http.max-persistent-connections-per-server", 10);
user_pref("network.http.max-connections", 900);

// Aggressively buffer video — reduces YouTube stuttering
user_pref("media.cache_readahead_limit", 99999);
user_pref("media.cache_resume_threshold", 99999);

// Reduce session save frequency (default 15000ms)
user_pref("browser.sessionstore.interval", 30000);

// No first-run noise
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.feeds.snippets", false);
