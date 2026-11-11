import XCTest

/// Error fallback page: HTTP 5xx interception, network failures, :r recovery,
/// and the plaintext-HTTP gate.
final class ErrorPageTests: E2ETestCase {

    func test502ShowsErrorPage() {
        app.openInCurrentTab("\(server.baseURL)/502")

        assertText("502 · Bad Gateway")
        assertText("The gateway received an invalid response")
        assertText(":r")
        assertText("to reload")
        assertServerHit("/502")
    }

    func test503ShowsErrorPage() {
        app.openInCurrentTab("\(server.baseURL)/503")

        assertText("503 · Service Unavailable")
        assertText("temporarily overloaded")
    }

    func testConnectionRefusedShowsErrorPage() throws {
        // A bound-then-released ephemeral port: guaranteed closed, and outside
        // WebKit's restricted-port list (which silently drops loads like :9).
        let closedPort = try TestHTTPServer.allocateClosedPort()
        app.openInCurrentTab("http://127.0.0.1:\(closedPort)/")

        assertText("ERR · Connection Failed")
        assertText("Could not connect to the server")
    }

    func testReloadReattemptsFailedURL() {
        app.openInCurrentTab("\(server.baseURL)/502")
        assertText("502 · Bad Gateway")

        server.clearLog()
        app.runCommand("r")
        // The failed URL must be re-requested from the origin, not the error HTML
        assertServerHit("/502")
        assertText("502 · Bad Gateway") // error page renders again for the retried 502
    }

    func testRecoveryNavigationAfterError() {
        app.openInCurrentTab("\(server.baseURL)/502")
        assertText("502 · Bad Gateway")

        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        assertText("alpha-marker")
    }

    func testSubframeFailureDoesNotClobberParentPage() throws {
        // A genuinely refused connection inside the iframe (not a WebKit
        // restricted-port silent drop) must not surface a main-frame error page.
        let closedPort = try TestHTTPServer.allocateClosedPort()
        server.route("/iframe-dead") { _ in
            .html(title: "Iframe Parent", """
            <p>parent-alive-marker</p>
            <iframe src="http://127.0.0.1:\(closedPort)/dead" width="100" height="50"></iframe>
            """)
        }

        app.openInCurrentTab("\(server.baseURL)/iframe-dead")

        assertText("Iframe Parent")
        assertText("parent-alive-marker")
        // The dead iframe must not surface a main-frame error page
        assertNoText("ERR ·", settle: 3.0)
    }

    func testPlainHttpPromptDecline() {
        app.openInCurrentTab("\(server.altBaseURL)/alpha")

        assertText("unencrypted (HTTP). Proceed?")
        app.tap("n")

        XCTAssertTrue(app.waitForTextToDisappear("unencrypted (HTTP)"))
        assertNoServerHit("/alpha")
        assertNoText("Alpha Page")
    }

    func testPlainHttpPromptAccept() {
        app.openInCurrentTab("\(server.altBaseURL)/alpha")

        assertText("unencrypted (HTTP). Proceed?")
        app.tap("y")

        assertText("Alpha Page")
        assertServerHit("/alpha")
    }

    func testPlainHttpPromptDefaultIsDecline() {
        app.openInCurrentTab("\(server.altBaseURL)/alpha")

        assertText("[y/N]") // default No
        app.sendKeys([.code(VimzenDriver.kReturn)])

        XCTAssertTrue(app.waitForTextToDisappear("unencrypted (HTTP)"))
        assertNoServerHit("/alpha")
    }
}
