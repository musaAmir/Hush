# Hush

A small Mac menu bar app that dims the background around the active window.

macOS 14+ · Apple silicon & Intel · Local development version 0.1.0

- Adjustable dimming intensity, with a preview.
- Toggle from the menu bar or **Control–Option–D**.
- Optional launch at login.
- Window events instead of repeated desktop polling; no screen capture or uploads.

Build: `./build.sh universal` · Test: `swift test`

Open `build/Hush.app`. Use **Enable Accessibility…** in Preferences, then approve Hush under System Settings → Privacy & Security → Accessibility. macOS requires this approval to follow other apps’ windows. A missing permission or unavailable window leaves the screen undimmed.

If Settings shows Hush enabled but Preferences still asks for access after restarting, remove its Accessibility entry and add the current `build/Hush.app` again. Rebuilding these ad-hoc signed development versions can invalidate an earlier permission grant.

These local builds are ad-hoc signed and not notarized. No update feed or public release has been configured yet.

Geometry tests cover Retina-independent coordinates, displays above/left of the primary display, spanning windows, and invalid readings. Live Accessibility tracking, Spaces, fullscreen apps, and multiple physical monitors require hands-on testing after approval.
