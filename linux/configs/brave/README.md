# Brave on Linux

Close Brave, then run `bash linux/setup.sh --brave-only` from the repository.
Full Linux setup also applies these settings when Brave is installed.

`appearance.json` records 120% interface scaling, 115% default page zoom,
17px standard page text, and 14px monospace text. Font families and themes are
unchanged. Interface scaling affects both browser controls and rendered pages.
Brave stores its profile in the Chromium layout (`Local State`, `Preferences`),
so the same keys Chrome used apply unchanged.

`preferences.json` is the rest of a hand-configured profile, captured on
2026-11-05 as dotted preference paths (diff a fresh profile's `Preferences`
against the configured one to add more):

- Leo (the AI assistant): toolbar button, context menu, autocomplete and tab
  organisation off; its sidebar entry hidden.
- Brave Rewards button, Wallet icon, side panel button and the new-tab page's
  background, Brave News, Rewards and Talk cards off; Brave News not opted in.
- Wide address bar showing full URLs (no elision); system title bar and
  borders instead of Brave's own frame.
- Google as the search engine in normal and private windows. The two
  dictionaries are what Brave itself wrote for that choice, minus the
  identifiers of the source profile.

`local-state.json` turns off P3A and metrics reporting (browser-wide, in
`Local State`).

Extensions are not installable from these files; sign in and add them by
hand: 1Password, uBlock Origin Lite, React Developer Tools, and the others on
the configured machine.

The setup command updates the user desktop launcher, including its new-window
and private-window actions. Launch Brave from the app launcher for scaling to
apply; direct terminal launches need `--force-device-scale-factor=1.2`.

Profile settings apply to Brave's last-used profile. Existing site zoom overrides
are preserved. Brave must be closed so it cannot overwrite the preferences.
Changed files are backed up beside the originals. Private Brave profile data
is never stored in this repository.
