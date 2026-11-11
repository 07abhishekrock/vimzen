import XCTest

/// Vim modal state machine: NORMAL / INSERT / COMMAND / SEARCH transitions.
final class ModeTests: E2ETestCase {

    func testBootsIntoNormalMode() {
        // setUp sanity already covers this, but keep an explicit regression test
        assertMode("NORMAL")
        assertTabCount(1)
        assertText("[pers]")
    }

    func testInsertModeEnterAndEscape() {
        app.sendKeys([.code(VimzenDriver.kI)])
        assertMode("INSERT")

        app.escape()
        assertMode("NORMAL")
    }

    func testInsertModeExitViaCtrlBracket() {
        app.sendKeys([.code(VimzenDriver.kI)])
        assertMode("INSERT")

        app.sendKeys([.code(VimzenDriver.kLeftBracket, mods: ["control"])])
        assertMode("NORMAL")
    }

    func testCommandModeEnterAndCancel() {
        app.sendKeys([.code(VimzenDriver.kSemicolon, mods: ["shift"])])
        assertMode("COMMAND")
        assertText(":q to close") // command placeholder hint

        app.escape()
        assertMode("NORMAL")
    }

    func testSearchModeEnterAndCancel() {
        app.sendKeys([.code(VimzenDriver.kSlash)])
        assertMode("SEARCH")

        app.escape()
        assertMode("NORMAL")
    }

    func testOpenPromptShowsCommandMode() {
        app.sendKeys([.code(VimzenDriver.kO)])
        assertMode("COMMAND")
        assertExactText("OPEN")
        assertText("vimzen://newtab") // current tab URL prefilled and selected

        app.escape()
        assertMode("NORMAL")
    }

    func testOpenNewTabPromptShowsPlaceholder() {
        app.sendKeys([.code(VimzenDriver.kO, mods: ["shift"])])
        assertMode("COMMAND")
        assertExactText("NEW TAB")
        assertText("Enter URL for new tab")

        app.escape()
        assertMode("NORMAL")
    }
}
