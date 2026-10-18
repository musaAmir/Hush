# Hush

A small Mac menu bar app that dims the background around the active window.

macOS 14+ · Apple silicon & Intel · Local development version 0.2.0

- Adjustable intensity and fades, with a visual preview. Fade duration: 0.05–2 seconds; smooth or linear, respecting Reduce Motion.
- Record separate toggle, enable and disable shortcuts. Default toggle: **Control–Option–D**. Conflicting shortcuts keep the previous assignment.
- Menu and Settings controls, temporary pauses for 5/15/60 minutes, and optional launch at login.
- Startup can remember the previous state, always enable, or start disabled.
- App exceptions pause dimming automatically while an excluded app is active.
- Window events instead of repeated desktop polling; no screen capture or uploads.
- Dimming sits behind the real window, preserving native corners during dragging and resizing without a moving cutout.

Build: `./build.sh universal` · Test: `swift test`

Open `build/Hush.app`. Open **Settings…** from the menu bar to customize it. Use **Enable Accessibility…** in General, then approve Hush under System Settings → Privacy & Security → Accessibility. macOS requires this approval to follow other apps’ windows. A missing permission or unavailable window leaves the screen undimmed.

If System Settings shows Hush enabled but Hush still asks for access after restarting, remove its Accessibility entry and add the current `build/Hush.app` again. Rebuilding these ad-hoc signed development versions can invalidate an earlier permission grant.

These local builds are ad-hoc signed and not notarized. No update feed or public release has been configured yet.

Pauses end automatically and are cleared when Hush quits. Settings and shortcuts are saved locally. Tests cover settings, shortcut routing and conflicts, interrupted animations, and actual window ordering before and after movement and resizing. Spaces, fullscreen apps, and multiple physical monitors still need hands-on verification before a public release.
