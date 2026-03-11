import Foundation
import CoreGraphics

// MARK: - Private CGS APIs

private typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: CGSConnectionID) -> UInt64

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
private func CGSCopyWindowsWithOptionsAndTags(
    _ cid: CGSConnectionID,
    _ owner: CGSConnectionID,
    _ spaces: CFArray,
    _ options: UInt32,
    _ setTags: UnsafeMutablePointer<UInt64>,
    _ clearTags: UnsafeMutablePointer<UInt64>
) -> CFArray?

// CGSSetWorkspace isn't exported in newer SDKs, load it at runtime via dlsym
private typealias CGSSetWorkspaceFunc = @convention(c) (CGSConnectionID, Int32) -> CGError
private let _CGSSetWorkspace: CGSSetWorkspaceFunc? = {
    guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "CGSSetWorkspace") else { return nil }
    return unsafeBitCast(sym, to: CGSSetWorkspaceFunc.self)
}()

// MARK: - SpaceInfo

struct SpaceInfo: Identifiable, Equatable {
    let id: UInt64
    let index: Int      // 1-based, used for switching
    let isActive: Bool
}

// MARK: - SpaceManager

enum SpaceManager {

    static func allSpaces() -> [SpaceInfo] {
        let cid = CGSMainConnectionID()
        guard let raw = CGSCopyManagedDisplaySpaces(cid),
              let displaySpaces = raw as? [[String: Any]] else { return [] }

        let activeId = CGSGetActiveSpace(cid)
        var result: [SpaceInfo] = []
        var index = 1

        for display in displaySpaces {
            guard let list = display["Spaces"] as? [[String: Any]] else { continue }
            for dict in list {
                guard let spaceId = dict["id64"] as? UInt64 else { continue }
                let type = dict["type"] as? Int ?? 0
                guard type == 0 else { continue }   // skip fullscreen/tiled spaces
                result.append(SpaceInfo(id: spaceId, index: index, isActive: spaceId == activeId))
                index += 1
            }
        }
        return result
    }

    static func activeSpaceID() -> UInt64 {
        CGSGetActiveSpace(CGSMainConnectionID())
    }

    static func windowIDs(inSpace spaceId: UInt64) -> Set<CGWindowID> {
        let cid = CGSMainConnectionID()
        let spaceArray = [spaceId] as CFArray
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        guard let raw = CGSCopyWindowsWithOptionsAndTags(cid, 0, spaceArray, 2, &setTags, &clearTags),
              let list = raw as? [CGWindowID] else { return [] }
        return Set(list)
    }

    /// Switch to a space by its 1-based index. Call before activating a window on that space.
    static func switchTo(spaceIndex: Int) {
        _CGSSetWorkspace?(CGSMainConnectionID(), Int32(spaceIndex))
    }
}
