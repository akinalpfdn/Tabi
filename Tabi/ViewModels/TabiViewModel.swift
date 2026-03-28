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
    var selectedSpaceId: UInt64? = nil    // nil = all windows
    var selectedIndex: Int = 0
    var isVisible: Bool = false
    var onOpenSettings: (() -> Void)?

    var windows: [WindowItem] {
        guard let spaceId = selectedSpaceId else { return allWindows }
        let ids = SpaceManager.windowIDs(inSpace: spaceId)
        return allWindows.filter { ids.contains($0.id) }
    }

    // MARK: - Private

    private let eventMonitor = EventMonitor()
    private var isLoading = false
    private var releasedDuringLoad = false
    private var mruOrder: [CGWindowID] = []

    // MARK: - Init

    init() {
        eventMonitor.onOptionTab = { [weak self] reverse in
            Task { @MainActor in
                await self?.handleOptionTab(reverse: reverse)
            }
        }
        eventMonitor.onOptionReleased = { [weak self] in
            guard let self else { return }
            if self.isLoading {
                self.releasedDuringLoad = true
            } else {
                self.activateSelected()
            }
        }
        eventMonitor.onEscape = { [weak self] in
            self?.dismiss()
        }
        eventMonitor.onSpaceShortcut = { [weak self] index in
            guard let self, self.isVisible else { return }
            if index == -1 {
                self.selectSpace(nil)
            } else {
                let desktops = self.spaces.filter { !$0.isFullscreen }
                if desktops.indices.contains(index) {
                    self.selectSpace(desktops[index])
                }
            }
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
        releasedDuringLoad = false

        // Load spaces, default to showing all windows
        spaces = SpaceManager.allSpaces()
        selectedSpaceId = nil

        // Load all windows across all spaces
        var items = await WindowEnumerator.allWindows()
        let thumbnails = await WindowCapturer.captureAll(windows: items)
        for i in items.indices {
            items[i].thumbnail = thumbnails[items[i].id]
        }

        WindowEnumerator.cacheAXElements(for: &items)

        // Add current frontmost window to MRU if not already tracked
        if let frontmost = items.first, !mruOrder.contains(frontmost.id) {
            mruOrder.insert(frontmost.id, at: 0)
        }

        // Reorder based on MRU history
        for (insertAt, mruId) in mruOrder.enumerated() {
            guard insertAt < items.count,
                  let currentIdx = items.firstIndex(where: { $0.id == mruId }),
                  currentIdx != insertAt else { continue }
            let item = items.remove(at: currentIdx)
            items.insert(item, at: insertAt)
        }

        allWindows = items
        selectedIndex = windows.count > 1 ? 1 : 0
        isLoading = false

        // Quick switch: Option was released before loading finished
        if releasedDuringLoad {
            releasedDuringLoad = false
            let list = windows
            if list.indices.contains(selectedIndex) {
                activateWindow(list[selectedIndex])
            }
            return
        }

        isVisible = true
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
        activateWindow(window)
        dismiss()
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
        mruOrder.removeAll { $0 == window.id }
        mruOrder.insert(window.id, at: 0)

        var psn = ProcessSerialNumber()
        GetProcessForPID(window.pid, &psn)
        _SLPSSetFrontProcessWithOptions(&psn, window.id, 0x200)
        makeKeyWindow(&psn, windowId: window.id)

        if let ax = window.axWindow {
            AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
        }
    }

    private func makeKeyWindow(_ psn: inout ProcessSerialNumber, windowId: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        var wid = windowId
        memcpy(&bytes[0x3c], &wid, MemoryLayout<UInt32>.size)
        memset(&bytes[0x20], 0xff, 0x10)
        bytes[0x08] = 0x01
        SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        SLPSPostEventRecordTo(&psn, &bytes)
    }
}

// MARK: - Private SPI

@_silgen_name("GetProcessForPID") @discardableResult
private func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
private func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo") @discardableResult
private func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError
