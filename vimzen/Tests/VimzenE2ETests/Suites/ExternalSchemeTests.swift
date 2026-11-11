import XCTest

/// Custom URL schemes (selfservicecapability://, mailto:, …) can't be loaded by
/// WKWebView. Vimzen must confirm, then hand off to the registered handler app.
/// The fixture scheme vimzene2e-test:// is deliberately unregistered, so the
/// accept path exercises LaunchServices failure → toast without opening an app.
final class ExternalSchemeTests: E2ETestCase {

    func testExternalLinkDeclineKeepsPage() {
        app.openInCurrentTab("\(server.baseURL)/external-links")
        assertText("external-links-marker")

        XCTAssertTrue(app.clickWebElement("ext-link"), "external link not found on page")
        assertText("vimzene2e-test://open?id=42")
        assertText("[Y/n]") // default Yes

        app.escape()
        XCTAssertTrue(app.waitForTextToDisappear("in an external app?"), "confirm did not dismiss on Escape")
        assertText("external-links-marker") // page untouched
        assertNoText("No app found", settle: 1.5)
    }

    func testExternalLinkAcceptWithoutHandlerShowsToast() {
        app.openInCurrentTab("\(server.baseURL)/external-links")
        assertText("external-links-marker")

        XCTAssertTrue(app.clickWebElement("ext-link"), "external link not found on page")
        assertText("in an external app?")

        app.sendKeys([.code(VimzenDriver.kReturn)]) // default Yes → attempts open
        assertText("No app found to open vimzene2e-test:// links", timeout: 8)
        assertText("external-links-marker") // still on the page
        assertTabCount(1)
    }

    /// The address bar must recognize custom schemes as URLs (never route them
    /// to Google search); the load then hits the same external-app confirm.
    func testTypedExternalSchemeURLShowsConfirm() {
        app.openInCurrentTab("vimzene2e-test://open?id=99")
        assertText("vimzene2e-test://open?id=99")
        assertText("in an external app?")

        app.escape()
        XCTAssertTrue(app.waitForTextToDisappear("in an external app?"), "confirm did not dismiss on Escape")
        assertTabCount(1)
        assertNoText("Google Search", settle: 1.5)
    }

    /// target=_blank with a custom scheme routes through createWebViewWith —
    /// the confirm appears but no dead tab is created, accepted or not.
    func testExternalTargetBlankCreatesNoTab() {
        app.openInCurrentTab("\(server.baseURL)/external-links")
        assertText("external-links-marker")

        XCTAssertTrue(app.clickWebElement("ext-blank-link"), "external blank link not found on page")
        assertText("vimzene2e-test://open?id=43")
        assertTabCount(1)

        app.escape()
        XCTAssertTrue(app.waitForTextToDisappear("in an external app?"), "confirm did not dismiss on Escape")
        assertTabCount(1)
    }
}
