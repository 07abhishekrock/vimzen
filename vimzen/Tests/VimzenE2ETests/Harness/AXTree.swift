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

    /// Finds the first AXMenuItem whose title exactly matches `needle` (e.g. an
    /// item of an open context menu) and presses it. Returns false when absent.
    @discardableResult
    static func pressMenuItem(pid: pid_t, titled needle: String) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var visited = 0
        guard let item = findMenuItem(element: app, needle: needle, visited: &visited, depth: 0) else {
            return false
        }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func findMenuItem(element: AXUIElement, needle: String, visited: inout Int, depth: Int) -> AXUIElement? {
        if depth > 40 || visited > 4000 { return nil }
        visited += 1

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if (roleRef as? String) == "AXMenuItem" {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
               (titleRef as? String) == needle {
                return element
            }
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findMenuItem(element: child, needle: needle, visited: &visited, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }

    /// Screen frame (Quartz top-left origin) of the first button/link whose label
    /// contains `needle` — used to click web-content elements with CGEvent.
    static func clickableFrame(pid: pid_t, titled needle: String) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        var visited = 0
        return findClickable(element: app, needle: needle, visited: &visited, depth: 0)
    }

    private static func findClickable(element: AXUIElement, needle: String, visited: inout Int, depth: Int) -> CGRect? {
        if depth > 40 || visited > 4000 { return nil }
        visited += 1

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if let role = roleRef as? String, role == "AXButton" || role == "AXLink" {
            var label: String?
            for attr in [kAXTitleAttribute, "AXLabel", kAXDescriptionAttribute, kAXValueAttribute] {
                var ref: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
                   let value = ref as? String, !value.isEmpty {
                    label = value
                    break
                }
            }
            if let label = label, label.contains(needle) {
                var posRef: CFTypeRef?, sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
                var point = CGPoint.zero
                var size = CGSize.zero
                if let posRef = posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &point) }
                if let sizeRef = sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) }
                if size.width > 0, size.height > 0 {
                    return CGRect(origin: point, size: size)
                }
            }
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findClickable(element: child, needle: needle, visited: &visited, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }
}
