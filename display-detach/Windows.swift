import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Window positions

/// Where a window lived before its display was disabled. Serialized to disk so
/// a later `restore-windows` run (after the monitors physically return) can put
/// it back. Windows are matched by app and title, then by order within the app.
struct WindowRecord: Codable {
    let pid: Int32
    let bundle: String?
    let title: String?
    let index: Int      // position in the app's window list when saved
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var position: CGPoint { CGPoint(x: x, y: y) }
    var size: CGSize { CGSize(width: width, height: height) }
}

let snapshotURL: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("display-detach", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("windows.json")
}()

func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(axValue as! AXValue, .cgPoint, &point) ? point : nil
}

func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(axValue as! AXValue, .cgSize, &size) ? size : nil
}

func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? Bool
}

func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
}

func axSet(_ element: AXUIElement, _ attribute: String, point: CGPoint) -> Bool {
    var p = point
    guard let v = AXValueCreate(.cgPoint, &p) else { return false }
    return AXUIElementSetAttributeValue(element, attribute as CFString, v) == .success
}

func axSet(_ element: AXUIElement, _ attribute: String, size: CGSize) -> Bool {
    var sz = size
    guard let v = AXValueCreate(.cgSize, &sz) else { return false }
    return AXUIElementSetAttributeValue(element, attribute as CFString, v) == .success
}

/// Live windows of every ordinary app, in each app's own window order.
func liveWindows() -> [(app: NSRunningApplication, element: AXUIElement, record: WindowRecord)] {
    var out: [(NSRunningApplication, AXUIElement, WindowRecord)] = []
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { continue }
        for (index, window) in windows.enumerated() {
            if axBool(window, kAXMinimizedAttribute) == true { continue }
            guard let position = axPoint(window, kAXPositionAttribute),
                  let size = axSize(window, kAXSizeAttribute) else { continue }
            let record = WindowRecord(
                pid: app.processIdentifier, bundle: app.bundleIdentifier,
                title: axString(window, kAXTitleAttribute), index: index,
                x: position.x, y: position.y, width: size.width, height: size.height)
            out.append((app, window, record))
        }
    }
    return out
}

/// Saves every visible window's frame. Needs the Accessibility permission;
/// without it this saves nothing and warns once.
@discardableResult
func saveWindowSnapshot() -> [WindowRecord] {
    guard AXIsProcessTrusted() else {
        warn("no Accessibility permission; window positions will not be saved")
        return []
    }
    let records = liveWindows().map { $0.record }
    do {
        let data = try JSONEncoder().encode(records)
        try data.write(to: snapshotURL, options: .atomic)
        print("saved \(records.count) window position(s)")
    } catch {
        warn("could not write window snapshot: \(error)")
    }
    return records
}

func displayContaining(_ point: CGPoint, in active: [CGDirectDisplayID]) -> CGDirectDisplayID? {
    active.first { CGDisplayBounds($0).contains(point) }
}

/// Finds the live window a saved record refers to: same app (pid, or bundle if
/// relaunched), then exact title, then the same index in the app's window list,
/// then the first remaining window of that app. Removes the match from `live`.
func takeMatch(for record: WindowRecord, from live: inout [(app: NSRunningApplication, element: AXUIElement, record: WindowRecord)]) -> (app: NSRunningApplication, element: AXUIElement, record: WindowRecord)? {
    let sameApp = live.indices.filter {
        live[$0].record.pid == record.pid
            || (record.bundle != nil && live[$0].record.bundle == record.bundle)
    }
    let index = sameApp.first { live[$0].record.title == record.title && record.title != nil }
        ?? sameApp.first { live[$0].record.index == record.index }
        ?? sameApp.first
    guard let i = index else { return nil }
    return live.remove(at: i)
}

func place(_ element: AXUIElement, at position: CGPoint, size: CGSize) -> Bool {
    // Position, size, position: some apps clamp the first move to the old display.
    _ = axSet(element, kAXPositionAttribute, point: position)
    _ = axSet(element, kAXSizeAttribute, size: size)
    return axSet(element, kAXPositionAttribute, point: position)
}

/// Moves saved windows back to their recorded frames. Only touches a window
/// whose recorded frame sits on a display that is active right now, so nothing
/// is ever pushed off-screen.
func restoreWindowSnapshot() throws {
    guard AXIsProcessTrusted() else { throw DetachError.accessibility }
    guard let data = try? Data(contentsOf: snapshotURL) else {
        print("nothing to restore (no snapshot saved yet)"); return
    }
    let records = try JSONDecoder().decode([WindowRecord].self, from: data)
    let active = try displayIDs(CGGetActiveDisplayList)
    var live = liveWindows()
    var moved = 0, skipped = 0

    for record in records {
        let center = CGPoint(x: record.x + record.width / 2, y: record.y + record.height / 2)
        guard displayContaining(center, in: active) != nil else { skipped += 1; continue }

        guard let target = takeMatch(for: record, from: &live) else { continue }
        let now = target.record
        let drifted = abs(now.x - record.x) > 1 || abs(now.y - record.y) > 1
        let resized = abs(now.width - record.width) > 1 || abs(now.height - record.height) > 1
        guard drifted || resized else { continue }
        if place(target.element, at: record.position, size: record.size) { moved += 1 }
    }
    print("restored \(moved) window position(s)" + (skipped > 0 ? ", \(skipped) skipped (display not active)" : ""))
}
