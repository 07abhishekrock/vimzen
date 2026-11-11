import XCTest

/// Base class for all Vimzen E2E suites. Every test gets:
/// - a fresh fixture HTTP server on an ephemeral port,
/// - a fresh app instance launched with `--vimzen-test-dir <tmp>`,
/// - full cleanup (app killed, server stopped, temp dir removed).
class E2ETestCase: XCTestCase {
    var server: TestHTTPServer!
    var app: VimzenDriver!
    var testDir: URL!

    override class func setUp() {
        super.setUp()
        VimzenDriver.killStaleTestInstances()
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        guard AXTree.isTrusted() else {
            throw XCTSkip("Accessibility permission required. Grant it to your terminal in System Settings → Privacy & Security → Accessibility.")
        }

        server = TestHTTPServer()
        server.registerDefaultFixtures()
        try server.start()

        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vimzen-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        app = VimzenDriver(testDir: testDir)
        try app.launch()
        app.focus()

        // Boot sanity: NORMAL mode, one scratchpad tab, personal profile, idle loader
        assertExactText("NORMAL", timeout: 15)
        assertText("1 tab", timeout: 5)
        assertText("[pers]", timeout: 5)
        assertText("Ready", timeout: 5)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        server?.stop()
        if let testDir = testDir {
            try? FileManager.default.removeItem(at: testDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Assertions

    func assertText(_ needle: String, timeout: TimeInterval = 12, file: StaticString = #filePath, line: UInt = #line) {
        if !app.waitForText(needle, timeout: timeout) {
            XCTFail("Expected text not found: \"\(needle)\"\nVisible texts: \(summaryOfVisibleTexts())", file: file, line: line)
        }
    }

    func assertExactText(_ needle: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        if !app.waitForExactText(needle, timeout: timeout) {
            XCTFail("Expected exact text not found: \"\(needle)\"\nVisible texts: \(summaryOfVisibleTexts())", file: file, line: line)
        }
    }

    /// Asserts the text is absent after a settle period (use for negative checks).
    func assertNoText(_ needle: String, settle: TimeInterval = 1.5, file: StaticString = #filePath, line: UInt = #line) {
        usleep(UInt32(settle * 1_000_000))
        let texts = app.allTexts()
        if texts.contains(where: { $0.contains(needle) }) {
            XCTFail("Unexpected text present: \"\(needle)\"\nVisible texts: \(summaryOfVisibleTexts())", file: file, line: line)
        }
    }

    func assertMode(_ mode: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        assertExactText(mode, timeout: timeout, file: file, line: line)
    }

    func assertTabCount(_ expected: Int, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let label = expected == 1 ? "1 tab" : "\(expected) tabs"
        assertText(label, timeout: timeout, file: file, line: line)
    }

    func assertServerHit(_ path: String, minCount: Int = 1, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if server.hits(path) >= minCount { return }
            usleep(100_000)
        }
        XCTFail("Server never received \(minCount)x hit for \(path) (got \(server.hits(path)))", file: file, line: line)
    }

    func assertNoServerHit(_ path: String, settle: TimeInterval = 1.5, file: StaticString = #filePath, line: UInt = #line) {
        usleep(UInt32(settle * 1_000_000))
        XCTAssertEqual(server.hits(path), 0, "Server unexpectedly received hit for \(path)", file: file, line: line)
    }

    private func summaryOfVisibleTexts() -> String {
        let texts = app.allTexts()
        let joined = texts.prefix(60).joined(separator: " | ")
        return texts.count > 60 ? "\(joined) … (\(texts.count) total)" : joined
    }
}
