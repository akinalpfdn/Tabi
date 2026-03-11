import Foundation
import AppKit
import ScreenCaptureKit

enum WindowEnumerator {

    static func allWindows() async -> [WindowItem] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
            return []
        }

        let excluded: Set<String> = ["Tabi", "Dock", "Window Server", "Control Center", "NotificationCenter"]

        return content.windows.compactMap { scWindow -> WindowItem? in
            guard let app = scWindow.owningApplication else { return nil }
            guard !excluded.contains(app.applicationName) else { return nil }
            guard scWindow.frame.width > 50, scWindow.frame.height > 50 else { return nil }

            let title = scWindow.title ?? app.applicationName
            let appIcon = NSWorkspace.shared.icon(forFile: appPath(for: app.processID) ?? "")

            return WindowItem(
                id: scWindow.windowID,
                title: title,
                appName: app.applicationName,
                appIcon: appIcon,
                bounds: scWindow.frame
            )
        }
    }

    private static func appPath(for pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleURL?.path
    }
}
