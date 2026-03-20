import Foundation
import AppKit
import ScreenCaptureKit

struct WindowItem: Identifiable, Equatable {
    let id: CGWindowID
    let title: String
    let appName: String
    let appIcon: NSImage?
    let bounds: CGRect
    let pid: pid_t
    var thumbnail: NSImage?
    var axWindow: AXUIElement?

    static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id
    }
}
