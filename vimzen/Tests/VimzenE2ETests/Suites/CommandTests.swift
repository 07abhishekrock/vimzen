import XCTest

/// Ex-commands and status-bar feedback: version, cert, js toggle,
/// mute controls, media cycling, unknown command.
final class CommandTests: E2ETestCase {

    func testVersionCommand() {
        app.runCommand("version")
        assertText("Vimzen v")
    }

    func testCertCommandOnPlainHttp() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        app.runCommand("cert")
        assertText("Insecure connection")
    }

    func testJavaScriptToggle() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        app.runCommand("js off")
        assertText("JavaScript: OFF (isolated)")

        app.runCommand("js on")
        assertText("JavaScript: ON")
    }

    func testMuteAndUnmute() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        app.runCommand("mute")
        assertText("Muted: Alpha Page")
        assertText("[MUTED]")

        app.runCommand("unmute")
        assertText("Unmuted: Alpha Page")
        XCTAssertTrue(app.waitForTextToDisappear("[MUTED]"))
    }

    func testMuteViaCtrlM() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        app.sendKeys([.code(VimzenDriver.kM, mods: ["control"])])
        assertText("[MUTED]")
    }

    func testMediaCycleWithNoMediaShowsToast() {
        app.sendKeys([.code(VimzenDriver.kM, mods: ["shift"])]) // M
        assertText("No media tabs playing or recently active")
    }

    func testUnknownCommandIsHarmless() {
        app.runCommand("xyzzy")

        assertMode("NORMAL")
        assertTabCount(1)
        assertText("Ready")
    }
}
