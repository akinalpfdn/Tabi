import Foundation
import AppKit
import Observation

// MARK: - TabiViewModel

@MainActor
@Observable
final class TabiViewModel {

    // MARK: - State

    var windows: [WindowItem] = []
    var selectedIndex: Int = 0
    var isVisible: Bool = false

    // MARK: - Private

    private let eventMonitor = EventMonitor()
    private var isLoading = false

    // MARK: - Init

    init() {
        eventMonitor.onOptionTab = { [weak self] reverse in
            Task { @MainActor in
                await self?.handleOptionTab(reverse: reverse)
            }
        }
        eventMonitor.onOptionReleased = { [weak self] in
            self?.activateSelected()
        }
        eventMonitor.onEscape = { [weak self] in
            self?.dismiss()
        }
        eventMonitor.start()
    }

    deinit {
        Task { @MainActor [weak self] in self?.eventMonitor.stop() }
    }

    // MARK: - Actions

    private func handleOptionTab(reverse: Bool) async {
        if !isVisible {
            await showSwitcher()
        } else {
            cycle(reverse: reverse)
        }
    }

    private func showSwitcher() async {
        guard !isLoading else { return }
        isLoading = true

        var items = await WindowEnumerator.allWindows()
        let thumbnails = await WindowCapturer.captureAll(windows: items)
        for i in items.indices {
            items[i].thumbnail = thumbnails[items[i].id]
        }

        windows = items
        // Start at index 1 (skip current window, select next)
        selectedIndex = windows.count > 1 ? 1 : 0
        isVisible = true
        isLoading = false
    }

    func cycle(reverse: Bool) {
        guard !windows.isEmpty else { return }
        if reverse {
            selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        } else {
            selectedIndex = (selectedIndex + 1) % windows.count
        }
    }

    func activateSelected() {
        guard isVisible, windows.indices.contains(selectedIndex) else {
            dismiss()
            return
        }
        let window = windows[selectedIndex]
        dismiss()
        activateWindow(window)
    }

    func select(_ item: WindowItem) {
        if let index = windows.firstIndex(of: item) {
            selectedIndex = index
            activateSelected()
        }
    }

    func close(_ item: WindowItem) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == item.appName }) else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        for axWindow in axWindows {
            var idVal: CGWindowID = 0
            _ = _AXUIElementGetWindow(axWindow, &idVal)
            guard idVal == item.id else { continue }
            var closeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeRef) == .success else { return }
            AXUIElementPerformAction(closeRef as! AXUIElement, kAXPressAction as CFString)
            windows.removeAll { $0.id == item.id }
            if windows.isEmpty { dismiss() } else { selectedIndex = min(selectedIndex, windows.count - 1) }
            return
        }
    }

    func dismiss() {
        isVisible = false
        windows = []
        selectedIndex = 0
    }

    // MARK: - Window activation

    private func activateWindow(_ window: WindowItem) {
        guard let app = NSRunningApplication(processIdentifier: pid_t(
            NSWorkspace.shared.runningApplications
                .first(where: { $0.localizedName == window.appName })?.processIdentifier ?? 0
        )) else { return }

        app.activate()

        // Raise the specific window via Accessibility
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        for axWindow in axWindows {
            var idVal: CGWindowID = 0
            _ = _AXUIElementGetWindow(axWindow, &idVal)
            if idVal == window.id {
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                break
            }
        }
    }
}

// Private CoreGraphics SPI for getting CGWindowID from AXUIElement
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError
