// display-detach: disable/enable individual external displays so their
// monitors lose signal and auto-detect another input.
//
// Uses the private CoreGraphics call CGSConfigureDisplayEnabled, the same
// mechanism BetterDisplay's "Disconnect" uses. Changes are session-scoped:
// a logout or reboot restores every display regardless of what this tool did.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(
    _ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ enabled: Bool
) -> CGError

func run() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { throw DetachError.usage }
    args.removeFirst()

    switch command {
    case "list":
        try list()
    case "windows":
        // Diagnostic: shows whether Accessibility is granted and what would be saved.
        let live = liveWindows()
        for w in live {
            print("\(w.app.localizedName ?? "?") [\(w.record.title ?? "")]: \(Int(w.record.x)),\(Int(w.record.y)) \(Int(w.record.width))x\(Int(w.record.height))")
        }
        print("\(live.count) window(s); accessibility trusted: \(AXIsProcessTrusted()); snapshot file: \(snapshotURL.path)")
    case "off":
        guard !args.isEmpty else { throw DetachError.usage }
        try off(args)
    case "on":
        guard !args.isEmpty else { throw DetachError.usage }
        try on(args)
    case "switch":
        var hold: TimeInterval = 10
        if let i = args.firstIndex(of: "--hold") {
            guard i + 1 < args.count, let h = TimeInterval(args[i + 1]), h >= 0 else { throw DetachError.usage }
            hold = h
            args.removeSubrange(i...(i + 1))
        }
        guard !args.isEmpty else { throw DetachError.usage }
        let all = try inventory()
        let targets = try resolve(args, in: all)
        // Every display's mode and origin: disabling two monitors can shift the
        // others' positions in the global arrangement as well.
        let layout = captureLayout(all.filter { $0.active })
        let records = saveWindowSnapshot(onDisplays: targets.map { $0.id })
        let disabled = try off(args)
        Thread.sleep(forTimeInterval: hold)
        // Re-enable by numeric ID no matter what happened during the hold, so
        // the Mac keeps outputting a signal for the monitors to return to later.
        try setEnabled(disabled, true)
        for d in disabled { print("on   id=\(d.id)  \(d.uuid)  \(d.name)") }
        restoreLayout(layout)
        // Park the monitors' windows on the MacBook screen so they are usable
        // while the monitors show Linux. `restore-windows` undoes this once the
        // monitors are physically back.
        Thread.sleep(forTimeInterval: 1.0)
        parkWindows(records, from: disabled.map { $0.id })
    case "save-windows":
        saveWindowSnapshot()
    case "restore-windows":
        try restoreWindowSnapshot()
    default:
        throw DetachError.usage
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write("display-detach: \(error)\n".data(using: .utf8)!)
    exit(1)
}
