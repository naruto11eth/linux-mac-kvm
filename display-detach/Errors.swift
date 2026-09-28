import CoreGraphics
import Foundation

func warn(_ message: String) {
    FileHandle.standardError.write("display-detach: warning: \(message)\n".data(using: .utf8)!)
}

enum DetachError: Error, CustomStringConvertible {
    case unknownDisplay(String)
    case builtin(String)
    case wouldBlankEverything
    case cg(String, CGError)
    case accessibility
    case usage

    var description: String {
        switch self {
        case .unknownDisplay(let u): return "no online display with UUID \(u)"
        case .builtin(let u): return "refusing to touch the built-in display \(u)"
        case .wouldBlankEverything: return "refusing: that would leave no active display"
        case .cg(let step, let err): return "\(step) failed with CGError \(err.rawValue)"
        case .accessibility: return "Accessibility permission is required for window restore"
        case .usage:
            return """
            usage:
              display-detach list
              display-detach off <uuid>...
              display-detach on  <uuid>...
              display-detach switch [--hold SECONDS] <uuid>...   (off, wait, on)
            """
        }
    }
}
