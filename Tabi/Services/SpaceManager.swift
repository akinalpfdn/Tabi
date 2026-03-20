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

// MARK: - SpaceInfo

struct SpaceInfo: Identifiable, Equatable {
    let id: UInt64
    let isActive: Bool
    let isFullscreen: Bool
}

// MARK: - SpaceManager

enum SpaceManager {

    static func allSpaces() -> [SpaceInfo] {
        let cid = CGSMainConnectionID()
        guard let raw = CGSCopyManagedDisplaySpaces(cid),
              let displaySpaces = raw as? [[String: Any]] else { return [] }

        let activeId = CGSGetActiveSpace(cid)
        var result: [SpaceInfo] = []

        for display in displaySpaces {
            guard let list = display["Spaces"] as? [[String: Any]] else { continue }
            for dict in list {
                guard let spaceId = dict["id64"] as? UInt64 else { continue }
                let type = dict["type"] as? Int ?? 0
                let isFullscreen = type != 0
                result.append(SpaceInfo(id: spaceId, isActive: spaceId == activeId, isFullscreen: isFullscreen))
            }
        }
        return result
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
}
