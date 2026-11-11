import XCTest

/// Command-bar hint combobox: read-only list filtered from CommandCatalog as
/// you type — no cycling, no Tab-fill, no click-commit; Enter always executes
/// the raw typed text. Empty query shows the persisted MRU-5 (full catalog
/// fallback when nothing has been recorded yet). The help page renders its
/// command tables from the same catalog.
final class CommandPickerTests: E2ETestCase {

    // macOS virtual keycodes not in VimzenDriver's constant list
    private let kDownArrow: UInt16 = 125
    private let kUpArrow: UInt16 = 126

    private func openCommandBar() {
        app.sendKeys([.code(VimzenDriver.kSemicolon, mods: ["shift"])])
        _ = app.waitForExactText("COMMAND", timeout: 5)
    }

    // MARK: - Hint list behavior

    func testHintsFilterAsYouType() {
        // Fresh test dir → no recents → full catalog on empty query
        openCommandBar()
        assertText("tabnew [url]")

        app.sendKeys([.type("dom")], interDelay: 0.25)
        assertText("domain [<key> on|off|reset]", timeout: 5)
        assertNoText("tabnew", settle: 1.5)
        app.escape()
        assertMode("NORMAL")
    }

    /// Arrows must not cycle and Enter must execute the typed text, not a row.
    /// Bare "domain" lists the host's settings summary; if a row were selected,
    /// its display ("domain [<key> on|off|reset]") would parse as an invalid
    /// key and show the Usage toast instead.
    func testReadonlyListArrowsAndEnterExecuteTypedText() {
        openCommandBar()
        app.sendKeys([.type("domain")], interDelay: 0.25)
        assertText("domain [<key> on|off|reset]", timeout: 5)

        app.sendKeys([.code(kDownArrow), .code(kDownArrow), .code(kUpArrow)], interDelay: 0.2)
        app.sendKeys([.code(VimzenDriver.kReturn)])

        assertText("popups-require-confirmation=default", timeout: 5)
        assertNoText("Usage: :domain", settle: 1.0)
    }

    // MARK: - MRU recents

    func testRecentsShownOnEmptyQueryAndPersistAcrossRelaunch() throws {
        // Full catalog fallback before anything is recorded
        openCommandBar()
        assertText("tabnew [url]")
        app.escape()

        app.runCommand("version")
        assertText("Vimzen v", timeout: 5)
        app.runCommand("cert")
        usleep(500_000)

        // Empty query now shows recents only, most recent first
        openCommandBar()
        assertText("Inspect TLS certificate chain")
        assertText("Show build info")
        assertNoText("tabnew", settle: 1.5)
        app.escape()

        // Recents survive an app relaunch with the same data dir
        app.terminate()
        app = VimzenDriver(testDir: testDir)
        try app.launch()
        app.focus()
        assertExactText("NORMAL", timeout: 15)

        openCommandBar()
        assertText("Inspect TLS certificate chain")
        assertText("Show build info")
        app.escape()
    }

    func testRecentsCappedAtFive() {
        // Six distinct commands → the oldest ("version") falls out of the MRU-5
        for cmd in ["version", "cert", "js", "mute", "unmute", "alias x"] {
            app.runCommand(cmd)
            usleep(500_000)
        }

        openCommandBar()
        assertText("alias <name>")
        assertText("unmute")
        assertNoText("Show build info", settle: 1.5) // "version" row is gone
        app.escape()
    }

    // MARK: - Single source: help page

    func testHelpPageRendersCatalogCommands() {
        app.runCommand("help")
        assertText("Vimzen Manual & Keymap")
        // Section headers render uppercase via CSS text-transform
        assertText("COMMANDS · PRIVACY & SECURITY")
        assertText(":domain")
        assertText("Per-domain settings, persisted across profiles")
    }
}
