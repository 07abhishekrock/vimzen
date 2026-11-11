import XCTest

/// In-page find: match counting, n/N cycling, no-match feedback.
final class FindTests: E2ETestCase {

    private func openAlpha() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
    }

    func testFindShowsMatchCount() {
        openAlpha()

        app.startFind("e2efindtoken")
        assertMode("SEARCH")
        assertText("[1/2]", timeout: 10)
    }

    func testFindNextPrevious() {
        openAlpha()

        app.startFind("e2efindtoken")
        assertText("[1/2]", timeout: 10)
        app.submitFind()
        assertMode("NORMAL")

        // Enter itself advances the match (submit runs a forward find), so after
        // submit the page sits on match 2: `n` wraps to 1, `N` steps back to 2.
        // Toasts live only 1.5s — poll while the key is delivered.
        XCTAssertTrue(app.sendKeysAndWaitForText([.type("n")], text: "[1/2]  /e2efindtoken"))
        XCTAssertTrue(app.sendKeysAndWaitForText([.code(VimzenDriver.kN, mods: ["shift"])], text: "[2/2]  /e2efindtoken"))
    }

    func testFindNoMatch() {
        openAlpha()

        app.startFind("zzznotfound")
        assertText("[0/0]", timeout: 10)
        app.submitFind()

        assertText("Pattern not found: zzznotfound")
    }

    func testFindCancelReturnsToNormal() {
        openAlpha()

        app.startFind("e2efindtoken")
        assertMode("SEARCH")

        app.escape()
        assertMode("NORMAL")
    }
}
