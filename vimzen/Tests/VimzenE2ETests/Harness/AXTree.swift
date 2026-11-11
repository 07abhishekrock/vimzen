import AppKit
import ApplicationServices

/// Reads the accessibility tree of the app under test and enumerates on-screen windows.
enum AXTree {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// All string values/titles/labels/descriptions found anywhere in the app's AX tree.
    static func texts(pid: pid_t) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        var out: [String] = []
        var visited = 0
        collect(element: app, into: &out, visited: &visited, depth: 0)
        return out
    }

    private static func collect(element: AXUIElement, into out: inout [String], visited: inout Int, depth: Int) {
        if depth > 40 || visited > 4000 { return }
        visited += 1

        for attr in [kAXValueAttribute, kAXTitleAttribute, "AXLabel", kAXDescriptionAttribute, "AXPlaceholderValue"] {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
               let value = ref as? String,
               !value.isEmpty {
                out.append(value)
            }
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                collect(element: child, into: &out, visited: &visited, depth: depth + 1)
            }
        }
    }

    /// Screen bounds (Quartz top-left origin) of the app's main window.
    static func windowBounds(pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in list {
            guard let ownerPid = window[kCGWindowOwnerPID as String] as? pid_t, ownerPid == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: bounds["X"]!, y: bounds["Y"]!, width: bounds["Width"]!, height: bounds["Height"]!)
            if rect.width > 400, rect.height > 300 {
                return rect
            }
        }
        return nil
    }
}
