import Foundation
import AppKit
import ScreenCaptureKit

struct WindowItem: Identifiable, Equatable {
    let id: CGWindowID
    let title: String
    let appName: String
    let appIcon: NSImage?
    let bounds: CGRect
    var thumbnail: NSImage?

    static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id
    }
}
