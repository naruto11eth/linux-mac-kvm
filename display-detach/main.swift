// display-detach: disable/enable individual external displays so their
// monitors lose signal and auto-detect another input.
//
// Uses the private CoreGraphics call CGSConfigureDisplayEnabled, the same
// mechanism BetterDisplay's "Disconnect" uses. Changes are session-scoped:
// a logout or reboot restores every display regardless of what this tool did.

import AppKit
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
        let disabled = try off(args)
        Thread.sleep(forTimeInterval: hold)
        // Re-enable by numeric ID no matter what happened during the hold, so
        // the Mac keeps outputting a signal for the monitors to return to later.
        try setEnabled(disabled, true)
        for d in disabled { print("on   id=\(d.id)  \(d.uuid)  \(d.name)") }
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
