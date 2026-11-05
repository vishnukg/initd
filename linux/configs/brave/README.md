# Brave appearance on Linux

Close Brave, then run `bash linux/setup.sh --brave-only` from the repository.
Full Linux setup also applies these settings when Brave is installed.

`appearance.json` records 120% interface scaling, 115% default page zoom,
17px standard page text, and 14px monospace text. Font families and themes are
unchanged. Interface scaling affects both browser controls and rendered pages.
Brave stores its profile in the Chromium layout (`Local State`, `Preferences`),
so the same keys Chrome used apply unchanged.

The setup command updates the user desktop launcher, including its new-window
and private-window actions. Launch Brave from the app launcher for scaling to
apply; direct terminal launches need `--force-device-scale-factor=1.2`.

Profile settings apply to Brave's last-used profile. Existing site zoom overrides
are preserved. Brave must be closed so it cannot overwrite the preferences.
Changed files are backed up beside the originals. Private Brave profile data
is never stored in this repository.
