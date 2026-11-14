import XCTest

/// New-tab scratchpad notes: persistence into the isolated test dir and
/// restoration on subsequent scratchpad loads.
final class ScratchpadTests: E2ETestCase {

    // Profile.personal.id — notes are stored per profile
    private let personalNotesFile = "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D.md"

    func testNotesPersistToIsolatedStore() {
        // Initial tab is the new-tab scratchpad
        app.sendKeys([.code(VimzenDriver.kI)])
        assertMode("INSERT")
        app.tap("z") // scratchpad editor receives DOM input in INSERT mode

        let notesURL = testDir
            .appendingPathComponent("scratchpads", isDirectory: true)
            .appendingPathComponent(personalNotesFile)

        let deadline = Date().addingTimeInterval(8)
        var contents = ""
        while Date() < deadline {
            contents = (try? String(contentsOf: notesURL, encoding: .utf8)) ?? ""
            if contents.contains("z") { break }
            usleep(200_000)
        }
        XCTAssertTrue(contents.contains("z"), "scratchpad notes never persisted; file contents: '\(contents)'")
    }

    func testNotesRestoreOnFreshScratchpad() {
        app.sendKeys([.code(VimzenDriver.kI)])
        assertMode("INSERT")
        app.typeChord("e2enotes")

        app.escape()
        assertMode("NORMAL")

        // Reload the scratchpad in the same tab → saved notes must be restored
        app.openInCurrentTab("vimzen://newtab")
        assertText("e2enotes", timeout: 10)
    }

    func testCaretStartsAtEndWhenReenteringInsert() {
        app.sendKeys([.code(VimzenDriver.kI)])
        assertMode("INSERT")
        app.typeChord("first")

        app.escape()
        assertMode("NORMAL")

        // Re-entering INSERT must land the caret after "first", not before it
        app.sendKeys([.code(VimzenDriver.kI)])
        assertMode("INSERT")
        app.typeChord("second")

        let notesURL = testDir
            .appendingPathComponent("scratchpads", isDirectory: true)
            .appendingPathComponent(personalNotesFile)

        let deadline = Date().addingTimeInterval(8)
        var contents = ""
        while Date() < deadline {
            contents = (try? String(contentsOf: notesURL, encoding: .utf8)) ?? ""
            if contents.contains("second") { break }
            usleep(200_000)
        }
        XCTAssertEqual(contents, "firstsecond", "caret did not land at end of existing notes: '\(contents)'")
    }
}
