import AppKit
import ApplicationServices

/// Tracks window focus changes across all apps using AX observers.
/// Maintains an MRU (most recently used) list of window IDs.
final class WindowTracker {

    private(set) var mruOrder: [CGWindowID] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    var suppressNotifications = false

    init() {
        startObservingApps()
    }

    deinit {
        stopAll()
    }

    // MARK: - MRU management

    func pushToFront(_ windowId: CGWindowID) {
        mruOrder.removeAll { $0 == windowId }
        mruOrder.insert(windowId, at: 0)
    }

    // MARK: - App lifecycle

    private func startObservingApps() {
        let deactivated = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.trackFocusedWindow(of: app)
        }

        let activated = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.trackFocusedWindow(of: app)
        }

        workspaceObservers = [deactivated, activated]
    }

    private func trackFocusedWindow(of app: NSRunningApplication) {
        guard !suppressNotifications else { return }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let focusedWindow = focusedRef else { return }

        let axWindow = focusedWindow as! AXUIElement
        var windowId: CGWindowID = 0
        _AXUIElementGetWindow(axWindow, &windowId)
        guard windowId != 0 else { return }

        pushToFront(windowId)
    }

    private func stopAll() {
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }
}
