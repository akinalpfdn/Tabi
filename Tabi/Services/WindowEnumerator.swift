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
                bounds: scWindow.frame
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

    /// Returns a mapping of windowID → z-order index (0 = frontmost).
    private static func windowZOrder() -> [CGWindowID: Int] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
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

    private static func appPath(for pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleURL?.path
    }
}
