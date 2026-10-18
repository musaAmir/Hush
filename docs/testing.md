# Local verification

`swift test` covers ownership/bounds matching, invalid readings, floating window levels, and opacity bounds. An AppKit integration test creates a real window and verifies that all dimming panels remain behind it after a large move and resize without any tracker update. It requires a logged-in Window Server session. `./build.sh universal` builds and ad-hoc signs Apple silicon and Intel binaries targeting macOS 14.

Accessibility approval was verified on this Mac. The initial renderer used a floating overlay with an enlarged, fixed-radius cutout: its corners did not match Finder and it trailed the window while dragging. Version 0.1.1 uses solid dimming panels ordered below the actual focused window. Native window shape and movement are now handled by the compositor. There is no movement subscription, cutout radius, position-following timer, or custom full-screen path redraw.

The front app's Accessibility focus/lifecycle events identify its focused window. Public Window Server metadata (ID, owner, bounds, level and alpha) resolve its ordering number without capturing pixels or requesting Screen Recording. At most one Accessibility read is in flight; stale results are discarded and focus events are coalesced in one main-loop turn. Unmatched, unavailable or unsupported windows leave the screen undimmed. Menus and system-level windows remain above the normal shade.

Manually check normal windows, rapid dragging, resize, app switching, same-app windows, dialogs, fullscreen, Spaces, display connection changes and sleep/wake before a public release. Overlays must ignore mouse input and never take keyboard focus. Keep the updated binary unchanged while checking permissions: an ad-hoc rebuild can invalidate its existing Accessibility entry.

The 0.1.1 build passes four core tests and the Window Server ordering regression. The original renderer failed that regression before the change. Final visual confirmation of the user's Finder dragging/corner scenario is pending renewed Accessibility approval for this rebuilt binary.
