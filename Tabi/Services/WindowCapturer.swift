import Foundation
import AppKit
import ScreenCaptureKit

enum WindowCapturer {

    static func captureAll(windows: [WindowItem]) async -> [CGWindowID: NSImage] {
        // Fetch content once for all spaces, then capture in parallel
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return [:]
        }

        let scWindowMap: [CGWindowID: SCWindow] = Dictionary(
            uniqueKeysWithValues: content.windows.compactMap { w in
                (w.windowID, w)
            }
        )

        return await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
            for window in windows {
                guard let scWindow = scWindowMap[window.id] else { continue }
                group.addTask {
                    let image = await capture(scWindow: scWindow)
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

    private static func capture(scWindow: SCWindow) async -> NSImage? {
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
}
