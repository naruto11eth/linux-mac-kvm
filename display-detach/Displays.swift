import AppKit
import CoreGraphics
import Foundation

struct DisplayInfo {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let active: Bool
    let builtin: Bool
}

/// Mode and position of a display captured before it is disabled, so the
/// re-enable can put it back exactly where macOS had it.
func displayIDs(_ fetch: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError) throws -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard fetch(0, nil, &count) == .success else { throw DetachError.cg("display count", .failure) }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard fetch(count, &ids, &count) == .success else { throw DetachError.cg("display list", .failure) }
    return Array(ids.prefix(Int(count)))
}

func uuidString(_ id: CGDirectDisplayID) -> String {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(id) else { return "?" }
    return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
}

func screenNames() -> [CGDirectDisplayID: String] {
    var names: [CGDirectDisplayID: String] = [:]
    for screen in NSScreen.screens {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            names[CGDirectDisplayID(num.uint32Value)] = screen.localizedName
        }
    }
    return names
}

func inventory() throws -> [DisplayInfo] {
    let online = try displayIDs(CGGetOnlineDisplayList)
    let active = Set(try displayIDs(CGGetActiveDisplayList))
    let names = screenNames()
    return online.map { id in
        DisplayInfo(
            id: id,
            uuid: uuidString(id),
            name: names[id] ?? "(inactive)",
            active: active.contains(id),
            builtin: CGDisplayIsBuiltin(id) != 0
        )
    }
}

func resolve(_ uuids: [String], in displays: [DisplayInfo]) throws -> [DisplayInfo] {
    try uuids.map { wanted in
        guard let d = displays.first(where: { $0.uuid.caseInsensitiveCompare(wanted) == .orderedSame }) else {
            throw DetachError.unknownDisplay(wanted)
        }
        guard !d.builtin else { throw DetachError.builtin(wanted) }
        return d
    }
}

func setEnabled(_ targets: [DisplayInfo], _ enabled: Bool) throws {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else {
        throw DetachError.cg("begin configuration", .failure)
    }
    for d in targets {
        let err = CGSConfigureDisplayEnabled(cfg, d.id, enabled)
        guard err == .success else {
            CGCancelDisplayConfiguration(cfg)
            throw DetachError.cg("configure \(d.uuid)", err)
        }
    }
    let err = CGCompleteDisplayConfiguration(cfg, .forSession)
    guard err == .success else { throw DetachError.cg("complete configuration", err) }
}

/// Disables the displays and returns them, so a caller can re-enable by the
/// numeric ID: once disabled, macOS no longer resolves the display's UUID.
@discardableResult
func off(_ uuids: [String]) throws -> [DisplayInfo] {
    let all = try inventory()
    let targets = try resolve(uuids, in: all)
    let targetIDs = Set(targets.map { $0.id })
    let remaining = all.filter { $0.active && !targetIDs.contains($0.id) }
    guard !remaining.isEmpty else { throw DetachError.wouldBlankEverything }
    try setEnabled(targets, false)
    for d in targets { print("off  id=\(d.id)  \(d.uuid)  \(d.name)") }
    return targets
}

func on(_ uuids: [String]) throws {
    let all = try inventory()
    let targets = try resolve(uuids, in: all)
    try setEnabled(targets, true)
    for d in targets { print("on   id=\(d.id)  \(d.uuid)  \(d.name)") }
}

func list() throws {
    for d in try inventory() {
        let state = d.active ? "active  " : "disabled"
        let kind = d.builtin ? "builtin " : "external"
        let b = CGDisplayBounds(d.id)
        let bounds = d.active ? "  at \(Int(b.minX)),\(Int(b.minY)) \(Int(b.width))x\(Int(b.height))" : ""
        print("\(state)  \(kind)  id=\(d.id)  \(d.uuid)  \(d.name)\(bounds)")
    }
}
