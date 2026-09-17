# Chrome appearance on Linux

Close Chrome, then run `bash linux/setup.sh --chrome-only` from the repository.
Full Linux setup also applies these settings when Chrome is installed.

`appearance.json` records 120% interface scaling, 115% default page zoom,
17px standard page text, and 14px monospace text. Font families and themes are
unchanged. Interface scaling affects both browser controls and rendered pages.

The setup command updates the user desktop launcher, including its new-window
and incognito actions. Launch Chrome from the app launcher for scaling to apply;
direct terminal launches need `--force-device-scale-factor=1.2`.

Profile settings apply to Chrome's last-used profile. Existing site zoom overrides
are preserved. Chrome must be closed so it cannot overwrite the preferences.
Changed files are backed up beside the originals. Private Chrome profile data
is never stored in this repository.
