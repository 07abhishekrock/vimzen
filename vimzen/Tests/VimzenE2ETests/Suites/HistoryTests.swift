import XCTest

/// SQLite-backed history: typed-visit recording, picker navigation,
/// clearing, and test-dir isolation.
final class HistoryTests: E2ETestCase {

    func testTypedVisitRecordedInIsolatedDatabase() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        // The history DB must live inside the per-test dir, never in real App Support
        let dbURL = testDir.appendingPathComponent("history.db")
        let deadline = Date().addingTimeInterval(8)
        var count = ""
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: dbURL.path) {
                count = queryVisitCount(dbURL: dbURL)
                if let n = Int(count), n >= 1 { break }
            }
            usleep(200_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path), "history.db missing in test dir")
        XCTAssertGreaterThan(Int(count) ?? 0, 0, "expected ≥1 visit row, got '\(count)'")
    }

    func testHistoryPickerNavigatesToVisitedPage() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        app.openInCurrentTab("\(server.baseURL)/beta")
        assertText("Beta Page")

        app.typeChord("gh")
        assertMode("COMMAND")
        assertExactText("HISTORY")
        app.sendKeys([.type("Alpha Page")])
        // Wait for the history row to appear, then select top row and commit
        usleep(800_000)
        app.sendKeys([
            .code(VimzenDriver.kJ, mods: ["control"]),
            .code(VimzenDriver.kReturn)
        ], interDelay: 0.3)

        assertText("alpha-marker") // navigated back to the alpha page
        assertMode("NORMAL")
    }

    func testClearHistory() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        app.runCommand("clearhistory")
        assertText("Cleared all history (Personal)")
    }

    private func queryVisitCount(dbURL: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbURL.path, "SELECT COUNT(*) FROM visits;"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard let _ = try? process.run() else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
