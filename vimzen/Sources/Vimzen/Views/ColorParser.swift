import AppKit

public enum ColorParser {
    public static func parse(_ input: String?) -> NSColor? {
        guard let raw = input?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        let str = raw.lowercased()
        if str == "transparent" || str == "rgba(0, 0, 0, 0)" || str == "rgba(0,0,0,0)" {
            return nil
        }

        // 1. Hex parsing (#rgb, #rrggbb, #rrggbbaa)
        if str.hasPrefix("#") {
            let hex = String(str.dropFirst())
            var intVal: UInt64 = 0
            guard Scanner(string: hex).scanHexInt64(&intVal) else { return nil }

            switch hex.count {
            case 3: // RGB (12-bit)
                let r = CGFloat((intVal >> 8) * 17) / 255.0
                let g = CGFloat((intVal >> 4 & 0xF) * 17) / 255.0
                let b = CGFloat((intVal & 0xF) * 17) / 255.0
                return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
            case 6: // RRGGBB (24-bit)
                let r = CGFloat((intVal >> 16) & 0xFF) / 255.0
                let g = CGFloat((intVal >> 8) & 0xFF) / 255.0
                let b = CGFloat(intVal & 0xFF) / 255.0
                return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
            case 8: // RRGGBBAA (32-bit)
                let r = CGFloat((intVal >> 24) & 0xFF) / 255.0
                let g = CGFloat((intVal >> 16) & 0xFF) / 255.0
                let b = CGFloat((intVal >> 8) & 0xFF) / 255.0
                let a = CGFloat(intVal & 0xFF) / 255.0
                if a < 0.1 { return nil }
                return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
            default:
                return nil
            }
        }

        // 2. rgb(r, g, b) or rgba(r, g, b, a)
        if str.hasPrefix("rgb") {
            let components = str
                .replacingOccurrences(of: "^rgba?\\(", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\)$", with: "", options: .regularExpression)
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            if components.count >= 3,
               let r = Double(components[0]),
               let g = Double(components[1]),
               let b = Double(components[2]) {
                let a = (components.count >= 4) ? (Double(components[3]) ?? 1.0) : 1.0
                if a < 0.05 { return nil }
                return NSColor(
                    calibratedRed: CGFloat(r / 255.0),
                    green: CGFloat(g / 255.0),
                    blue: CGFloat(b / 255.0),
                    alpha: CGFloat(a)
                )
            }
        }

        return nil
    }
}
