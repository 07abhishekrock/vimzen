import XCTest

/// Page loading, reload, back/forward, help page.
final class NavigationTests: E2ETestCase {

    func testOpenUrlInCurrentTab() {
        app.openInCurrentTab("\(server.baseURL)/alpha")

        assertText("Alpha Page")
        assertText("alpha-marker")
        assertText("Ready")
        assertServerHit("/alpha")
    }

    func testOpenUrlInNewTab() {
        app.openInNewTab("\(server.baseURL)/beta")

        assertTabCount(2)
        assertText("Beta Page")
        assertServerHit("/beta")
    }

    func testReload() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        server.clearLog()
        app.tap("r")
        assertServerHit("/alpha")
        assertText("Alpha Page")
    }

    func testReloadFromOrigin() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        server.clearLog()
        app.sendKeys([.code(VimzenDriver.kR, mods: ["shift"])])
        assertServerHit("/alpha")
    }

    func testReloadCommand() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        server.clearLog()
        app.runCommand("r")
        assertServerHit("/alpha")
    }

    func testBackForwardNavigation() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        app.openInCurrentTab("\(server.baseURL)/beta")
        assertText("Beta Page")

        app.sendKeys([.code(VimzenDriver.kH, mods: ["shift"])])
        assertText("Alpha Page")

        app.sendKeys([.code(VimzenDriver.kL, mods: ["shift"])])
        assertText("Beta Page")
    }

    func testHelpPageViaQuestionMark() {
        app.sendKeys([.code(VimzenDriver.kSlash, mods: ["shift"])]) // '?'
        assertText("Vimzen Help")
        assertText("Vimzen Manual & Keymap")
    }

    func testHelpPageViaCommand() {
        app.runCommand("help")
        assertText("Vimzen Help")
        assertText("Vimzen Manual & Keymap")
    }

    func testRedirectFollowed() {
        app.openInCurrentTab("\(server.baseURL)/redirect")
        assertText("Alpha Page")
        assertServerHit("/alpha")
    }

    func testScrollToBottomAndTop() {
        app.openInCurrentTab("\(server.baseURL)/tall")
        assertText("Tall Page")

        app.sendKeys([.code(VimzenDriver.kG, mods: ["shift"])])
        assertText("scrolled:", timeout: 10)

        app.typeChord("gg")
        assertText("scrolled:0", timeout: 10)
    }

    func testNormalModeKeysDoNotLeakIntoDOM() {
        app.openInCurrentTab("\(server.baseURL)/form")
        assertText("Form Page")
        app.escape() // ensure NORMAL even if the page editor had focus

        app.tap("j")
        app.tap("k")
        // If keys leaked into the focused input, the page title would become typed:jk
        assertNoText("typed:")
    }

    func testInsertModeTypesIntoDOM() {
        app.openInCurrentTab("\(server.baseURL)/form")
        assertText("Form Page")

        app.sendKeys([.code(VimzenDriver.kI)])
        assertMode("INSERT")
        app.tap("a")
        app.tap("b")

        assertText("typed:ab", timeout: 10)
    }
}
