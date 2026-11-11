import XCTest

/// Tab lifecycle: create, close + undo, cycling, last-active, same-domain,
/// aliases, and the tab picker.
final class TabTests: E2ETestCase {

    func testTabNewAndClose() {
        app.runCommand("t")
        assertTabCount(2)

        app.tap("x")
        assertTabCount(1)
        assertText("Closed:")
    }

    func testCloseTabUndoRestore() {
        app.openInNewTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        assertTabCount(2)

        app.tap("x")
        assertTabCount(1)
        assertText("Closed: Alpha Page")

        app.tap("u") // within the 4s undo window
        assertTabCount(2)
        assertText("Alpha Page")
    }

    func testTabCycling() {
        app.openInNewTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        app.openInNewTab("\(server.baseURL)/beta")
        assertText("Beta Page")

        // tabs: [scratchpad, alpha, beta], active = beta; gt wraps to scratchpad
        app.typeChord("gt")
        assertExactText("New Tab")

        app.typeChord("gt")
        assertText("Alpha Page")

        app.typeChord("gT")
        assertExactText("New Tab")
    }

    func testLastActiveTabViaCommandAndCtrl6() {
        app.openInNewTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        app.openInNewTab("\(server.baseURL)/beta")
        assertText("Beta Page")

        app.runCommand("b#")
        assertText("Alpha Page")

        app.sendKeys([.code(VimzenDriver.k6, mods: ["control"])])
        assertText("Beta Page")
    }

    func testSameDomainCycling() {
        app.openInNewTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        app.openInNewTab("\(server.baseURL)/beta")
        assertText("Beta Page")

        // Both tabs share host 127.0.0.1 → gd cycles back to alpha
        app.typeChord("gd")
        assertText("Alpha Page")
    }

    func testSameDomainCyclingSingleTabToast() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        app.typeChord("gd")
        assertText("Only 1 tab for 127.0.0.1")
    }

    func testTabAlias() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        app.runCommand("alias foo")
        assertText("@foo · Alpha Page")

        app.runCommand("alias")
        XCTAssertTrue(app.waitForTextToDisappear("@foo"))
    }

    func testTabPickerFuzzySwitch() {
        app.openInNewTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        app.openInNewTab("\(server.baseURL)/beta")
        assertText("Beta Page")

        app.tap("b")
        assertMode("COMMAND")
        assertExactText("TABS")
        app.sendKeys([.type("Alpha")])
        // Wait for the combobox to filter, then select the top row
        usleep(600_000)
        app.sendKeys([
            .code(VimzenDriver.kJ, mods: ["control"]),
            .code(VimzenDriver.kReturn)
        ], interDelay: 0.3)

        assertText("Alpha Page")
        assertMode("NORMAL")
    }
}
