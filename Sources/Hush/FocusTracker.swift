import AppKit
import ApplicationServices
import HushCore

final class FocusTracker {
    var onWindow: ((FocusedWindow?) -> Void)?
    var onPermission: ((Bool) -> Void)?
    private let queue = DispatchQueue(label: "com.musaamir.hush.accessibility", qos: .userInitiated)
    private var subscriptions: [NSObjectProtocol] = []
    private var enabled = false
    private var generation = 0
    private var readInFlight = false
    private var needsRefresh = false
    private var suspended = false
    private var pending: DispatchWorkItem?
    // Accessed only by the serial accessibility queue.
    private var observer: AXObserver?
    private var app: AXUIElement?
    private var window: AXUIElement?
    private var pid: pid_t = 0
    private let windowEvents = [kAXResizedNotification,
        kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]

    func start() {
        guard !enabled else { refresh(); return }
        enabled = true
        suspended = false
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            subscriptions.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            subscriptions.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspended = false
                self?.refresh()
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            subscriptions.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspended = true
                self?.generation += 1
                self?.onWindow?(nil)
            })
        }
        subscriptions.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        refresh()
    }

    func stop() {
        enabled = false
        needsRefresh = false
        generation += 1
        pending?.cancel(); pending = nil
        subscriptions.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        subscriptions.removeAll()
        queue.async { self.clearObservation() }
        onWindow?(nil)
    }

    func refresh() {
        guard enabled, !suspended else { return }
        guard pending == nil else { return }
        // Coalesce focus notifications within one main-loop turn. Window movement
        // needs no reads or redraws: the shade remains below the actual window.
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.readFrontWindow()
        }
        pending = work
        DispatchQueue.main.async(execute: work)
    }

    private func readFrontWindow() {
        guard enabled, !suspended else { return }
        generation += 1
        let token = generation
        let trusted = AXIsProcessTrusted()
        onPermission?(trusted)
        guard trusted, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            onWindow?(nil)
            queue.async { self.clearObservation() }
            return
        }
        guard !readInFlight else { needsRefresh = true; return }
        readInFlight = true
        let frontPID = front.processIdentifier
        queue.async {
            if self.pid != frontPID {
                self.clearObservation()
                self.pid = frontPID
                let element = AXUIElementCreateApplication(frontPID)
                AXUIElementSetMessagingTimeout(element, 0.15)
                self.app = element
                var created: AXObserver?
                if AXObserverCreate(frontPID, { _, _, _, context in
                    guard let context else { return }
                    let tracker = Unmanaged<FocusTracker>.fromOpaque(context).takeUnretainedValue()
                    DispatchQueue.main.async { tracker.refresh() }
                }, &created) == .success, let created {
                    self.observer = created
                    let context = Unmanaged.passUnretained(self).toOpaque()
                    for event in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXWindowCreatedNotification] {
                        AXObserverAddNotification(created, element, event as CFString, context)
                    }
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
                }
            }
            var focused: CFTypeRef?
            guard let app = self.app,
                  AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
                  let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
                self.deliver(nil, token: token); return
            }
            let focusedWindow = unsafeBitCast(focused, to: AXUIElement.self)
            if self.window == nil || !CFEqual(self.window!, focusedWindow) {
                if let old = self.window, let observer = self.observer {
                    self.windowEvents.forEach { AXObserverRemoveNotification(observer, old, $0 as CFString) }
                }
                self.window = focusedWindow
                if let observer = self.observer {
                    let context = Unmanaged.passUnretained(self).toOpaque()
                    self.windowEvents.forEach { AXObserverAddNotification(observer, focusedWindow, $0 as CFString, context) }
                }
            }
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(focusedWindow, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(focusedWindow, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionValue, let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
                self.deliver(nil, token: token); return
            }
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
                  AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else {
                self.deliver(nil, token: token); return
            }
            let frame = CGRect(origin: position, size: size)
            // IDs, bounds, ownership and levels only; never read titles or pixels.
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let candidates = info.compactMap { item -> WindowCandidate? in
                guard let owner = item[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == frontPID,
                      let number = item[kCGWindowNumber as String] as? NSNumber,
                      let level = item[kCGWindowLayer as String] as? NSNumber,
                      let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
                return WindowCandidate(number: number.intValue, level: level.intValue, ownerPID: owner.int32Value,
                                       frame: rect, alpha: (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
            }
            self.deliver(WindowMatching.focusedWindow(ownerPID: frontPID, frame: frame, candidates: candidates), token: token)
        }
    }

    private func deliver(_ window: FocusedWindow?, token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readInFlight = false
            if self.enabled, !self.suspended, self.generation == token { self.onWindow?(window) }
            if self.needsRefresh { self.needsRefresh = false; self.refresh() }
        }
    }
    private func clearObservation() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; app = nil; window = nil; pid = 0
    }
}
