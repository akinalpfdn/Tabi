import Foundation
import AppKit
import ScreenCaptureKit

enum WindowCapturer {

    static func capture(windowID: CGWindowID) async -> NSImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            return nil
        }

        let config = SCStreamConfiguration()
        config.width = max(Int(scWindow.frame.width), 1)
        config.height = max(Int(scWindow.frame.height), 1)
        config.showsCursor = false

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)

        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        ) else { return nil }

        return NSImage(cgImage: cgImage, size: scWindow.frame.size)
    }

    static func captureAll(windows: [WindowItem]) async -> [CGWindowID: NSImage] {
        await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
            for window in windows {
                group.addTask {
                    let image = await capture(windowID: window.id)
                    return (window.id, image)
                }
            }
            var results: [CGWindowID: NSImage] = [:]
            for await (id, image) in group {
                if let image { results[id] = image }
            }
            return results
        }
    }
}
