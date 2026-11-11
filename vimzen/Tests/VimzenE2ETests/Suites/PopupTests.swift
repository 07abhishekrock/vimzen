import XCTest

/// Popup behavior: window.open / target=_blank must open tabs, and JS
/// alert/confirm/prompt must surface native dialogs wired to their results.
final class PopupTests: E2ETestCase {

    // MARK: - window.open & target=_blank

    func testWindowOpenCreatesNewTab() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")

        XCTAssertTrue(app.clickWebElement("window-open-btn"), "window-open button not found on page")

        assertTabCount(2)
        assertText("Popup Target", timeout: 10)
        assertText("popup-target-marker")
        assertServerHit("/popup-target")
    }

    func testTargetBlankLinkCreatesNewTab() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")

        XCTAssertTrue(app.clickWebElement("blank-link"), "target=_blank link not found on page")

        assertTabCount(2)
        assertText("popup-target-marker", timeout: 10)
        assertServerHit("/popup-target")
    }

    /// The stock WebKit context menu's "Open Link in New Window" routes through
    /// the same createWebViewWith delegate as window.open — it must open a tab.
    func testContextMenuOpenInNewWindowCreatesNewTab() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")

        XCTAssertTrue(app.rightClickWebElement("plain-link"), "plain link not found on page")
        XCTAssertTrue(app.pressContextMenuItem("Open Link in New Window"), "context menu item never appeared")

        assertTabCount(2)
        assertText("popup-target-marker", timeout: 10)
        assertServerHit("/popup-target")
    }

    // MARK: - JavaScript dialogs

    func testAlertDialogShowsAndDismisses() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")

        XCTAssertTrue(app.clickWebElement("alert-btn"), "alert button not found on page")

        assertText("e2e-alert-msg", timeout: 8)
        app.sendKeys([.code(VimzenDriver.kReturn)])
        XCTAssertTrue(app.waitForTextToDisappear("e2e-alert-msg"), "alert did not dismiss on Return")
    }

    func testConfirmAccept() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")

        XCTAssertTrue(app.clickWebElement("confirm-btn"), "confirm button not found on page")

        assertText("e2e-confirm-msg", timeout: 8)
        app.sendKeys([.code(VimzenDriver.kReturn)])
        assertText("confirm:true", timeout: 8)
    }

    func testConfirmCancel() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")

        XCTAssertTrue(app.clickWebElement("confirm-btn"), "confirm button not found on page")

        assertText("e2e-confirm-msg", timeout: 8)
        app.escape()
        assertText("confirm:false", timeout: 8)
    }

    func testPromptSubmit() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")

        XCTAssertTrue(app.clickWebElement("prompt-btn"), "prompt button not found on page")

        assertText("e2e-prompt-msg", timeout: 8)
        app.typeChord("hello")
        app.sendKeys([.code(VimzenDriver.kReturn)])
        assertText("prompt:hello", timeout: 8)
    }

    func testPromptCancel() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")

        XCTAssertTrue(app.clickWebElement("prompt-btn"), "prompt button not found on page")

        assertText("e2e-prompt-msg", timeout: 8)
        app.escape()
        assertText("prompt:null", timeout: 8)
    }
}
