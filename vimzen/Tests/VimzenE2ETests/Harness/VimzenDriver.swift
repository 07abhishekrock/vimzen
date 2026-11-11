import AppKit

/// Drives a Vimzen instance launched in test mode: lifecycle, synthetic input,
/// and polling assertions over the accessibility tree.
///
/// Keyboard events are delivered through System Events (AppleScript), which is
/// reliable on this machine; mouse events use CGEvent, which is also reliable.
final class VimzenDriver {
    let testDir: URL
    private(set) var pid: pid_t = 0
    private var process: Process?
    private(set) var lastInputError: String?

    init(testDir: URL) {
        self.testDir = testDir
    }

    // MARK: - Paths

    static var packageRoot: URL {
        // .../browser/vimzen/Tests/VimzenE2ETests/Harness/VimzenDriver.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Harness
            .deletingLastPathComponent() // VimzenE2ETests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // vimzen package root
    }

    static var binaryURL: URL {
        packageRoot.appendingPathComponent(".build/debug/Vimzen")
    }

    // MARK: - Lifecycle

    /// Kills leftover debug instances from previous (possibly crashed) test runs.
    /// Never touches the user's installed app: only `.build/` binaries are matched.
    static func killStaleTestInstances() {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-ax", "-o", "pid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard let _ = try? ps.run() else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()

        let selfPid = ProcessInfo.processInfo.processIdentifier
        for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(".build/debug/Vimzen") || trimmed.contains("--vimzen-test-dir"),
                  let pidStr = trimmed.components(separatedBy: .whitespaces).first,
                  let pid = Int32(pidStr), pid != selfPid else { continue }
            kill(pid, SIGKILL)
        }
    }

    func launch() throws {
        let binary = VimzenDriver.binaryURL
        guard FileManager.default.fileExists(atPath: binary.path) else {
            throw NSError(
                domain: "E2E",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Vimzen binary not found at \(binary.path). Run scripts/e2e.sh (it builds first)."]
            )
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--vimzen-test-dir", testDir.path]

        let logURL = testDir.appendingPathComponent("app.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        self.process = process
        self.pid = process.processIdentifier

        // Wait for the window to appear on screen
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if !process.isRunning {
                let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                throw NSError(domain: "E2E", code: 3, userInfo: [NSLocalizedDescriptionKey: "Vimzen exited during launch.\n\(log)"])
            }
            if AXTree.windowBounds(pid: pid) != nil { return }
            usleep(150_000)
        }
        throw NSError(domain: "E2E", code: 4, userInfo: [NSLocalizedDescriptionKey: "Vimzen window never appeared"])
    }

    func terminate() {
        guard let process = process, process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && process.isRunning {
            usleep(100_000)
        }
        if process.isRunning {
            kill(pid, SIGKILL)
        }
        process.waitUntilExit()
    }

    // MARK: - Focus & mouse (CGEvent)

    func focus() {
        if let runningApp = NSRunningApplication(processIdentifier: pid) {
            runningApp.activate(options: [.activateAllWindows])
        }
        usleep(300_000)
        clickHeader()
        usleep(300_000)
    }

    func clickHeader(doubleClick: Bool = false) {
        guard let bounds = AXTree.windowBounds(pid: pid) else { return }
        let point = CGPoint(x: bounds.midX, y: bounds.minY + 12)
        postMouseClick(at: point, clickState: 1)
        if doubleClick {
            usleep(80_000)
            postMouseClick(at: point, clickState: 2)
        }
    }

    /// Clicks a web-content button/link (located via the AX tree by label) at its
    /// center using CGEvent. Returns false when no matching element is on screen.
    @discardableResult
    func clickWebElement(_ title: String) -> Bool {
        guard let frame = AXTree.clickableFrame(pid: pid, titled: title) else { return false }
        postMouseClick(at: CGPoint(x: frame.midX, y: frame.midY), clickState: 1)
        return true
    }

    /// Right-clicks a web-content link/button to open its context menu.
    /// Pair with pressContextMenuItem to choose an item.
    @discardableResult
    func rightClickWebElement(_ title: String) -> Bool {
        guard let frame = AXTree.clickableFrame(pid: pid, titled: title) else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .right)
        move?.post(tap: .cghidEventTap)
        usleep(100_000)
        let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
        down?.post(tap: .cghidEventTap)
        usleep(60_000)
        let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
        up?.post(tap: .cghidEventTap)
        return true
    }

    /// Presses an item of the currently open context menu (exact title match),
    /// polling briefly for the menu to appear. Returns false if it never shows.
    @discardableResult
    func pressContextMenuItem(_ title: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if AXTree.pressMenuItem(pid: pid, titled: title) { return true }
            usleep(150_000)
        }
        return false
    }

    private func postMouseClick(at point: CGPoint, clickState: Int64) {
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        usleep(60_000)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: clickState)
        down?.post(tap: .cghidEventTap)
        usleep(60_000)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        up?.setIntegerValueField(.mouseEventClickState, value: clickState)
        up?.post(tap: .cghidEventTap)
    }

    func dragHeader(dx: CGFloat, dy: CGFloat) {
        guard let bounds = AXTree.windowBounds(pid: pid) else { return }
        let start = CGPoint(x: bounds.midX, y: bounds.minY + 12)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        usleep(150_000)
        // Slow enough for the window server to track the pointer; a fast synthetic
        // drag outruns the window and it stops following partway
        let steps = 20
        for step in 1...steps {
            let point = CGPoint(x: start.x + dx * CGFloat(step) / CGFloat(steps),
                                y: start.y + dy * CGFloat(step) / CGFloat(steps))
            let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)
            drag?.post(tap: .cghidEventTap)
            usleep(40_000)
        }
        let end = CGPoint(x: start.x + dx, y: start.y + dy)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
        up?.post(tap: .cghidEventTap)
        usleep(150_000)
    }

    /// Waits until the window frame stops changing (zoom/restore is animated).
    @discardableResult
    func waitForWindowToSettle(timeout: TimeInterval = 5) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        var last = AXTree.windowBounds(pid: pid)
        while Date() < deadline {
            usleep(350_000)
            let current = AXTree.windowBounds(pid: pid)
            if let current = current, current == last { return current }
            last = current
        }
        return last
    }

    // MARK: - Keyboard (System Events)

    enum KeyAction {
        case code(UInt16, mods: [String] = [])
        case type(String)

        var scriptLine: String {
            switch self {
            case .code(let keyCode, let mods):
                if mods.isEmpty { return "key code \(keyCode)" }
                let flags = mods.map { "\($0) down" }.joined(separator: ", ")
                return "key code \(keyCode) using {\(flags)}"
            case .type(let text):
                var escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
                return "keystroke \"\(escaped)\""
            }
        }
    }

    // Key code constants (US layout)
    static let kEscape: UInt16 = 53
    static let kReturn: UInt16 = 36
    static let kTab: UInt16 = 48
    static let kA: UInt16 = 0
    static let kB: UInt16 = 11
    static let kG: UInt16 = 5
    static let kH: UInt16 = 4
    static let kI: UInt16 = 34
    static let kJ: UInt16 = 38
    static let kK: UInt16 = 40
    static let kL: UInt16 = 37
    static let kM: UInt16 = 46
    static let kN: UInt16 = 45
    static let kO: UInt16 = 31
    static let kP: UInt16 = 35
    static let kR: UInt16 = 15
    static let kT: UInt16 = 17
    static let kU: UInt16 = 32
    static let kX: UInt16 = 7
    static let kY: UInt16 = 16
    static let kSlash: UInt16 = 44
    static let kSemicolon: UInt16 = 41
    static let kLeftBracket: UInt16 = 33
    static let k6: UInt16 = 22

    /// Sends a batch of key actions in a single System Events call.
    func sendKeys(_ actions: [KeyAction], interDelay: TimeInterval = 0.25) {
        let process = makeAppleScriptProcess(actions, interDelay: interDelay)
        do {
            try process.run()
        } catch {
            lastInputError = "osascript failed to launch: \(error)"
            return
        }
        process.waitUntilExit()
        recordAppleScriptResult(process)
    }

    /// Sends keys and polls for `needle` *while the keys are being delivered*.
    /// Use this for short-lived UI like toasts (1.5s) that could expire between
    /// a blocking sendKeys() returning and the first AX poll.
    @discardableResult
    func sendKeysAndWaitForText(_ actions: [KeyAction], text needle: String, timeout: TimeInterval = 12, interDelay: TimeInterval = 0.25) -> Bool {
        let process = makeAppleScriptProcess(actions, interDelay: interDelay)
        do {
            try process.run()
        } catch {
            lastInputError = "osascript failed to launch: \(error)"
            return false
        }
        let found = waitForText(needle, timeout: timeout)
        process.waitUntilExit()
        recordAppleScriptResult(process)
        return found
    }

    private func makeAppleScriptProcess(_ actions: [KeyAction], interDelay: TimeInterval) -> Process {
        var lines: [String] = []
        for (index, action) in actions.enumerated() {
            lines.append(action.scriptLine)
            if index < actions.count - 1 {
                lines.append("delay \(String(format: "%.2f", interDelay))")
            }
        }

        var script = "tell application \"System Events\"\n"
        script += "set frontmost of (first process whose unix id is \(pid)) to true\n"
        script += "delay 0.3\n"
        script += lines.joined(separator: "\n")
        script += "\nend tell\n"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        appleScriptErrorPipe = errPipe
        return process
    }

    private var appleScriptErrorPipe: Pipe?

    private func recordAppleScriptResult(_ process: Process) {
        if process.terminationStatus != 0 {
            let err = appleScriptErrorPipe.map { String(decoding: $0.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) } ?? ""
            lastInputError = "osascript exit \(process.terminationStatus): \(err)"
        } else {
            lastInputError = nil
        }
    }

    // MARK: - High-level flows

    /// 'o' → clear prefilled URL → type → Enter
    func openInCurrentTab(_ url: String) {
        sendKeys([.code(VimzenDriver.kO)])
        _ = waitForExactText("COMMAND", timeout: 5)
        sendKeys([
            .code(VimzenDriver.kA, mods: ["command"]),
            .type(url),
            .code(VimzenDriver.kReturn)
        ], interDelay: 0.35)
    }

    /// 'O' → type → Enter
    func openInNewTab(_ url: String) {
        sendKeys([.code(VimzenDriver.kO, mods: ["shift"])])
        _ = waitForExactText("COMMAND", timeout: 5)
        sendKeys([
            .type(url),
            .code(VimzenDriver.kReturn)
        ], interDelay: 0.35)
    }

    /// ':' → type command (without leading colon) → Enter
    func runCommand(_ command: String) {
        sendKeys([.code(VimzenDriver.kSemicolon, mods: ["shift"])])
        _ = waitForExactText("COMMAND", timeout: 5)
        sendKeys([
            .type(command),
            .code(VimzenDriver.kReturn)
        ], interDelay: 0.35)
    }

    /// '/' → type query; leaves the search field open (mode stays SEARCH)
    func startFind(_ query: String) {
        sendKeys([.code(VimzenDriver.kSlash)])
        _ = waitForExactText("SEARCH", timeout: 5)
        sendKeys([.type(query)])
    }

    func submitFind() {
        sendKeys([.code(VimzenDriver.kReturn)])
    }

    func tap(_ character: String) {
        sendKeys([.type(character)])
    }

    /// Types a multi-key chord (e.g. "gt", "gg") in one batch, faster than the
    /// KeyEngine's 1000ms chord timeout.
    func typeChord(_ sequence: String) {
        sendKeys(sequence.map { .type(String($0)) }, interDelay: 0.12)
    }

    func escape() {
        sendKeys([.code(VimzenDriver.kEscape)])
    }

    // MARK: - Assertions (polling over the AX tree)

    @discardableResult
    func waitForText(_ needle: String, timeout: TimeInterval = 12) -> Bool {
        poll(timeout: timeout) {
            AXTree.texts(pid: self.pid).contains { $0.contains(needle) }
        }
    }

    /// Exact whole-element match (used for the mode badge label).
    @discardableResult
    func waitForExactText(_ needle: String, timeout: TimeInterval = 8) -> Bool {
        poll(timeout: timeout) {
            AXTree.texts(pid: self.pid).contains { $0 == needle }
        }
    }

    @discardableResult
    func waitForTextToDisappear(_ needle: String, timeout: TimeInterval = 8) -> Bool {
        poll(timeout: timeout) {
            !AXTree.texts(pid: self.pid).contains { $0.contains(needle) }
        }
    }

    func allTexts() -> [String] {
        AXTree.texts(pid: pid)
    }

    func tabCount() -> Int? {
        for text in allTexts() {
            if let match = text.wholeMatch(of: /^(\d+) tabs?$/) {
                return Int(match.1)
            }
        }
        return nil
    }

    @discardableResult
    func waitForWindow(_ predicate: @escaping (CGRect) -> Bool, timeout: TimeInterval = 10) -> CGRect? {
        var result: CGRect?
        _ = poll(timeout: timeout) {
            guard let bounds = AXTree.windowBounds(pid: self.pid), predicate(bounds) else { return false }
            result = bounds
            return true
        }
        return result
    }

    private func poll(timeout: TimeInterval, interval: UInt32 = 150_000, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(interval)
        }
        return condition()
    }
}
