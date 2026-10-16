# Local verification

`swift test` covers focused-window coordinate conversion, invalid geometry, opacity bounds, and clipping windows across displays above, beside, and left of the primary display. `./build.sh universal` builds and ad-hoc signs Apple silicon and Intel binaries targeting macOS 14.

Preferences and its interactive dimming preview were inspected on this Mac without Accessibility permission. Real tracking needs macOS Accessibility approval. Test normal windows, move/resize, app switching, dialogs, fullscreen, Spaces, display connection changes, and sleep/wake before a public release. Overlays ignore mouse input and hide when the active window cannot be read.

The dimmer subscribes only to the front app's relevant Accessibility events, with short messaging timeouts on a serial queue. At most one read is in flight; stale results are discarded and event bursts coalesced. It has no repeating timer, screen capture, or network code.
