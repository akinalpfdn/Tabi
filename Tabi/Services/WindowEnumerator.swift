import Foundation
import AppKit
import ScreenCaptureKit

enum WindowEnumerator {

    static func allWindows() async -> [WindowItem] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return []
        }

        // Only include apps with regular activation policy (visible in Dock)
        let userAppPIDs: Set<Int32> = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map { $0.processIdentifier }
        )

        let excludedNames: Set<String> = ["Tabi", "Dock", "Window Server", "Control Center",
                                          "NotificationCenter", "Spotlight", "universalAccessAuthWarn"]

        // Get z-order (front-to-back = MRU) from CGWindowList
        let zOrder = Self.windowZOrder()

        var items = content.windows.compactMap { scWindow -> WindowItem? in
            guard let app = scWindow.owningApplication else { return nil }
            guard userAppPIDs.contains(app.processID) else { return nil }
            guard !excludedNames.contains(app.applicationName) else { return nil }
            guard scWindow.frame.width > 100, scWindow.frame.height > 100 else { return nil }
            guard let title = scWindow.title, !title.isEmpty else { return nil }

            let appIcon = NSWorkspace.shared.icon(forFile: appPath(for: app.processID) ?? "")

            return WindowItem(
                id: scWindow.windowID,
                title: title,
                appName: app.applicationName,
                appIcon: appIcon,
                bounds: scWindow.frame,
                pid: app.processID
            )
        }

        // Sort by z-order: frontmost (most recent) first
        items.sort { a, b in
            let ai = zOrder[a.id] ?? Int.max
            let bi = zOrder[b.id] ?? Int.max
            return ai < bi
        }

        return items
    }

    /// windowID → z-order index (0 = frontmost).
    private static func windowZOrder() -> [CGWindowID: Int] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        for (index, info) in infoList.enumerated() {
            if let id = info[kCGWindowNumber as String] as? CGWindowID {
                order[id] = index
            }
        }
        return order
    }

    static func cacheAXElements(for items: inout [WindowItem]) {
        let byPid = Dictionary(grouping: items.indices, by: { items[$0].pid })

        for (pid, indices) in byPid {
            let appElement = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let axWindows = windowsRef as? [AXUIElement] {
                for axWindow in axWindows {
                    var idVal: CGWindowID = 0
                    _AXUIElementGetWindow(axWindow, &idVal)
                    if let idx = indices.first(where: { items[$0].id == idVal }) {
                        items[idx].axWindow = axWindow
                    }
                }
            }

            let missingIndices = indices.filter { items[$0].axWindow == nil }
            guard !missingIndices.isEmpty else { continue }

            let missingIds = Set(missingIndices.map { items[$0].id })
            let bruteForceElements = axElementsByBruteForce(pid: pid)

            for axWindow in bruteForceElements {
                var idVal: CGWindowID = 0
                _AXUIElementGetWindow(axWindow, &idVal)
                if missingIds.contains(idVal),
                   let idx = missingIndices.first(where: { items[$0].id == idVal }) {
                    items[idx].axWindow = axWindow
                }
            }
        }
    }

    private static func axElementsByBruteForce(pid: pid_t) -> [AXUIElement] {
        var remoteToken = Data(count: 20)
        remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        remoteToken.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })

        var results = [AXUIElement]()
        let start = DispatchTime.now()

        for elementId: UInt64 in 0..<1000 {
            remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementId) { Data($0) })
            guard let ax = _AXUIElementCreateWithRemoteToken(remoteToken as CFData)?.takeRetainedValue() else { continue }

            var subroleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, kAXSubroleAttribute as CFString, &subroleRef) == .success,
                  let subrole = subroleRef as? String,
                  subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String
            else { continue }

            results.append(ax)

            let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            if elapsed > 100_000_000 { break }
        }
        return results
    }

    private static func appPath(for pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleURL?.path
    }
}

@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken") @discardableResult
private func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?
