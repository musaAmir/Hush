# Local verification

`swift test` covers ownership/bounds matching, invalid readings, floating window levels, and opacity bounds. An AppKit integration test creates a real window and verifies that all dimming panels remain behind it after a large move and resize without any tracker update. It requires a logged-in Window Server session. `./build.sh universal` builds and ad-hoc signs Apple silicon and Intel binaries targeting macOS 14.

Accessibility approval was verified on this Mac. The initial renderer used a floating overlay with an enlarged, fixed-radius cutout: its corners did not match Finder and it trailed the window while dragging. Version 0.1.1 uses solid dimming panels ordered below the actual focused window. Native window shape and movement are now handled by the compositor. There is no movement subscription, cutout radius, position-following timer, or custom full-screen path redraw.

The front app's Accessibility focus/lifecycle events identify its focused window. Public Window Server metadata (ID, owner, bounds, level and alpha) resolve its ordering number without capturing pixels or requesting Screen Recording. At most one Accessibility read is in flight; stale results are discarded and focus events are coalesced in one main-loop turn. Unmatched, unavailable or unsupported windows leave the screen undimmed. Menus and system-level windows remain above the normal shade.

Manually check normal windows, rapid dragging, resize, app switching, same-app windows, dialogs, fullscreen, Spaces, display connection changes and sleep/wake before a public release. Overlays must ignore mouse input and never take keyboard focus. Keep the updated binary unchanged while checking permissions: an ad-hoc rebuild can invalidate its existing Accessibility entry.

The 0.1.1 build passed four core tests and the Window Server ordering regression. The original renderer failed that regression before the change. The rebuilt app was reopened and its renewed Accessibility approval confirmed in Preferences. The user confirmed the Finder dragging/corner fix works.

## Version 0.2.0

Fades use explicit compositor opacity animations on solid layer-backed panels, still below the real window. Switching focus restarts the background fade; repeated updates of the same window do not restart it. A transition generation prevents an interrupted fade-out from hiding newer focus. Disabling fades or Reduce Motion finishes pending animation immediately. There is no animation timer or work after a fade finishes. Temporary pauses use one one-shot timer, invalidated on resume, toggle, or quit.

Nine core checks cover migration of existing preferences, startup policy, fade limits and Reduce Motion, persisted/cleared shortcuts, invalid shortcut data, app exclusions, window matching and opacity. Three AppKit checks cover window ordering, interrupted fade completion and animation cleanup, and Carbon hotkey routing/registration conflicts. The hotkey test sends events directly to this process's event target; physical keyboard delivery still needs a hands-on check.

The separate `com.musaamir.hush.settingspreview` development bundle was used to inspect all four settings tabs without replacing the user's working app. Native UI checks verified pause/resume status, adjustable fade duration and preview, recording a custom shortcut, rejecting a duplicate, and adding/removing an app exception. Test settings use the preview's defaults domain. The preview was quit and moved under `build/debug-investigation/`. The universal 0.2.0 app was then launched, its Accessibility entry renewed, and access confirmed after restarting. Appearance was left open with the default 0.50-second smooth fade. Physical keyboard delivery and the feel of live window-switch fades remain hands-on checks.

## Version 0.2.1

Settings now use a full-height AppKit sidebar with colored section icons, the page title in the toolbar, grouped cards with switches, and keycap-style shortcuts. Hush stays menu bar-only; its Dock icon and app menu appear only while Settings is open. No dependencies or background tasks were added. Existing preferences and dimming behavior are unchanged.

The isolated settings preview (since removed) was used to inspect General, Appearance, Shortcuts, and Exceptions, invoke the fade preview, start/cancel shortcut recording, and add/remove an app exception. The empty and populated exception lists were visually checked. The existing 12 tests and universal build are the release checks.

On this macOS 27 toolchain, the default SwiftPM Xcode backend recorded SDK 14.0 in the executable even with the 27.0 SDK selected. The release script uses native SwiftPM instead: `vtool -show-build` must show SDK 27.0 and minimum macOS 14.0 in both slices. Native SwiftPM is deprecated in this toolchain; reassess this workaround when upgrading SwiftPM.

## Updates (Sparkle)

Hush uses Sparkle 2.10 (SwiftPM) for in-app updates. The feed is `appcast.xml` on `main` (`SUFeedURL`), and each release zip is a GitHub release asset signed with the EdDSA key in the login Keychain (account `com.musaamir.hush`). `scripts/release.sh "notes"` builds, signs, creates the release and publishes the feed. Back up the private key with `generate_keys --account com.musaamir.hush -x <file>`; without it, existing installs cannot accept updates.

An end-to-end check used a 0.2.1 copy with a separate bundle ID and a local signed feed: it downloaded a 9.9.9 build automatically and replaced itself on quit with a valid signature. Ad-hoc signing changes the code identity each release, so Accessibility must be re-granted after every update until releases use a stable signing certificate.
