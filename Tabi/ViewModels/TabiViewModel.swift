import Foundation
import AppKit
import Observation

// MARK: - TabiViewModel

@MainActor
@Observable
final class TabiViewModel {

    // MARK: - State

    var allWindows: [WindowItem] = []
    var spaces: [SpaceInfo] = []
    var selectedSpaceId: UInt64? = nil    // nil = active space
    var selectedIndex: Int = 0
    var isVisible: Bool = false

    var windows: [WindowItem] {
        guard let spaceId = selectedSpaceId else { return allWindows }
        let ids = SpaceManager.windowIDs(inSpace: spaceId)
        return allWindows.filter { ids.contains($0.id) }
    }

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

        // Load spaces, default to active space
        spaces = SpaceManager.allSpaces()
        selectedSpaceId = spaces.first(where: { $0.isActive })?.id

        // Load all windows across all spaces
        var items = await WindowEnumerator.allWindows()
        let thumbnails = await WindowCapturer.captureAll(windows: items)
        for i in items.indices {
            items[i].thumbnail = thumbnails[items[i].id]
        }

        allWindows = items
        selectedIndex = windows.count > 1 ? 1 : 0
        isVisible = true
        isLoading = false
    }

    func selectSpace(_ space: SpaceInfo?) {
        selectedSpaceId = space?.id
        selectedIndex = 0
    }

    func cycle(reverse: Bool) {
        let list = windows
        guard !list.isEmpty else { return }
        if reverse {
            selectedIndex = (selectedIndex - 1 + list.count) % list.count
        } else {
            selectedIndex = (selectedIndex + 1) % list.count
        }
    }

    func activateSelected() {
        let list = windows
        guard isVisible, list.indices.contains(selectedIndex) else {
            dismiss()
            return
        }
        let window = list[selectedIndex]
        dismiss()
        activateWindow(window)
    }

    func select(_ item: WindowItem) {
        let list = windows
        if let index = list.firstIndex(of: item) {
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
            allWindows.removeAll { $0.id == item.id }
            let list = windows
            if list.isEmpty { dismiss() } else { selectedIndex = min(selectedIndex, list.count - 1) }
            return
        }
    }

    func dismiss() {
        isVisible = false
        allWindows = []
        spaces = []
        selectedSpaceId = nil
        selectedIndex = 0
    }

    // MARK: - Window activation

    private func activateWindow(_ window: WindowItem) {
        // If window is on a different space, switch to it first
        if let spaceId = selectedSpaceId,
           let space = spaces.first(where: { $0.id == spaceId }),
           !space.isActive {
            SpaceManager.switchTo(spaceIndex: space.index)
        }

        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == window.appName }) else { return }

        app.activate()

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
