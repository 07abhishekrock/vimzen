import AppKit

public enum Mode: String, CaseIterable, Sendable {
    case normal = "NORMAL"
    case insert = "INSERT"
    case search = "SEARCH"
    case hint = "HINT"
    case command = "COMMAND"

    public var badgeText: String {
        return rawValue
    }

    public var badgeBackgroundColor: NSColor {
        switch self {
        case .normal:
            return NSColor(calibratedRed: 0.18, green: 0.80, blue: 0.44, alpha: 1.0) // Green
        case .insert:
            return NSColor(calibratedRed: 0.20, green: 0.60, blue: 1.00, alpha: 1.0) // Blue
        case .search:
            return NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0) // Yellow
        case .hint:
            return NSColor(calibratedRed: 0.91, green: 0.30, blue: 0.24, alpha: 1.0) // Red
        case .command:
            return NSColor(calibratedRed: 0.61, green: 0.35, blue: 0.71, alpha: 1.0) // Purple
        }
    }

    public var badgeTextColor: NSColor {
        switch self {
        case .normal, .search:
            return NSColor(calibratedWhite: 0.1, alpha: 1.0)
        default:
            return NSColor.white
        }
    }
}
