import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct SavedLayout {
    let id: CGDirectDisplayID
    let mode: CGDisplayMode?
    let origin: CGPoint
}

func captureLayout(_ targets: [DisplayInfo]) -> [SavedLayout] {
    targets.map { SavedLayout(id: $0.id, mode: CGDisplayCopyDisplayMode($0.id), origin: CGDisplayBounds($0.id).origin) }
}

/// Best effort: a failure here leaves the display on but possibly rearranged,
/// which is far better than leaving it disabled, so it only warns.
func restoreLayout(_ saved: [SavedLayout]) {
    guard !saved.isEmpty else { return }
    // Wait for every display to be active again (up to 5 s) before configuring it.
    for _ in 0..<20 {
        let active = Set((try? displayIDs(CGGetActiveDisplayList)) ?? [])
        if saved.allSatisfy({ active.contains($0.id) }) { break }
        Thread.sleep(forTimeInterval: 0.25)
    }
    // Only touch displays whose mode or position actually drifted.
    let drifted = saved.filter { s in
        let sameMode: Bool = {
            guard let want = s.mode, let now = CGDisplayCopyDisplayMode(s.id) else { return true }
            return now.width == want.width && now.height == want.height
                && now.pixelWidth == want.pixelWidth && now.pixelHeight == want.pixelHeight
                && abs(now.refreshRate - want.refreshRate) < 0.5
        }()
        return !sameMode || CGDisplayBounds(s.id).origin != s.origin
    }
    guard !drifted.isEmpty else { return }
    let saved = drifted
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else {
        warn("layout restore: begin configuration failed"); return
    }
    for s in saved {
        // The saved mode object belongs to the old framebuffer; find the same
        // mode in the re-enabled display's fresh list before applying it.
        if let mode = s.mode {
            if let fresh = matchingMode(for: s.id, like: mode) {
                if CGConfigureDisplayWithDisplayMode(cfg, s.id, fresh, nil) != .success {
                    warn("layout restore: mode for id=\(s.id) rejected")
                }
            } else {
                warn("layout restore: no matching mode for id=\(s.id)")
            }
        }
        if CGConfigureDisplayOrigin(cfg, s.id, Int32(s.origin.x), Int32(s.origin.y)) != .success {
            warn("layout restore: origin for id=\(s.id) rejected")
        }
    }
    if CGCompleteDisplayConfiguration(cfg, .forSession) != .success {
        warn("layout restore: complete configuration failed")
    }
}

func matchingMode(for id: CGDirectDisplayID, like wanted: CGDisplayMode) -> CGDisplayMode? {
    let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return nil }
    let sameGeometry = modes.filter {
        $0.width == wanted.width && $0.height == wanted.height
            && $0.pixelWidth == wanted.pixelWidth && $0.pixelHeight == wanted.pixelHeight
    }
    // Prefer the same refresh rate; some panels report 60 vs 59.94 between
    // connects, so fall back to any mode with the same geometry.
    return sameGeometry.first { abs($0.refreshRate - wanted.refreshRate) < 0.5 } ?? sameGeometry.first
}
