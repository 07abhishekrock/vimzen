import XCTest

/// Per-domain settings (:domain command) — persisted globally, shared across
/// profiles. Each test launches with a fresh --vimzen-test-dir, so the store
/// starts empty except in the explicit relaunch-persistence test.
final class DomainSettingsTests: E2ETestCase {

    private var downloadsDir: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    private func cleanFixtureFiles() {
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(atPath: downloadsDir.path) {
            for item in items where item.hasPrefix("e2e-fixture") {
                try? fm.removeItem(at: downloadsDir.appendingPathComponent(item))
            }
        }
    }

    override func tearDownWithError() throws {
        cleanFixtureFiles()
        try super.tearDownWithError()
    }

    // MARK: - :domain command

    func testDomainCommandListsDefaults() {
        app.openInCurrentTab("\(server.baseURL)/")
        assertText("home-root-marker")

        app.runCommand("domain")
        assertText("popups-require-confirmation=default")
        assertText("javascript=default")
        assertText("mute-audio=default")
    }

    func testDomainCommandRejectsUnknownKey() {
        app.openInCurrentTab("\(server.baseURL)/")
        assertText("home-root-marker")

        app.runCommand("domain bogus-key on")
        assertText("Usage: :domain <key> on|off|reset")
    }

    // MARK: - popups-require-confirmation

    func testPopupGateAccept() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")
        app.runCommand("domain popups-require-confirmation on")
        assertText("popups-require-confirmation=on")

        XCTAssertTrue(app.clickWebElement("window-open-btn"), "window-open button not found on page")
        assertText("Allow popup to")
        assertText("[y/N]") // default No

        app.tap("y")
        assertTabCount(2)
        assertText("popup-target-marker", timeout: 10)
        assertServerHit("/popup-target")
    }

    func testPopupGateDeny() {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")
        app.runCommand("domain popups-require-confirmation on")
        assertText("popups-require-confirmation=on")

        XCTAssertTrue(app.clickWebElement("window-open-btn"), "window-open button not found on page")
        assertText("[y/N]")

        app.sendKeys([.code(VimzenDriver.kReturn)]) // Return = default No
        assertNoServerHit("/popup-target", settle: 2.0)
        assertTabCount(1)
    }

    // MARK: - javascript

    func testJavaScriptOnByDefault() {
        app.openInCurrentTab("\(server.baseURL)/js-check")
        assertText("js-check-marker")
        assertText("js-on-marker")
        assertNoText("js-off-marker")
    }

    func testJavaScriptOffForMarkedDomain() {
        app.openInCurrentTab("\(server.baseURL)/")
        assertText("home-root-marker")
        app.runCommand("domain javascript off")
        assertText("javascript=off")

        app.openInCurrentTab("\(server.baseURL)/js-check")
        assertText("js-check-marker")
        assertText("js-off-marker")
        assertNoText("js-on-marker")
    }

    // MARK: - allow-insecure-http

    func testInsecureGateShownByDefault() {
        app.openInCurrentTab("\(server.altBaseURL)/")
        assertText("unencrypted")
        assertText("[y/N]")

        app.sendKeys([.code(VimzenDriver.kReturn)]) // decline
        XCTAssertTrue(app.waitForTextToDisappear("unencrypted"), "insecure prompt did not dismiss")
    }

    func testInsecureGateSkippedForMarkedDomain() {
        // Pass the gate once so the tab sits on the non-localhost host
        app.openInCurrentTab("\(server.altBaseURL)/")
        assertText("unencrypted")
        app.tap("y")
        assertText("home-root-marker", timeout: 10)

        app.runCommand("domain allow-insecure-http on")
        assertText("allow-insecure-http=on")

        // A different path on the same host isn't in the session bypass list —
        // only the domain setting lets it through without the gate
        app.openInCurrentTab("\(server.altBaseURL)/alpha")
        assertText("alpha-marker", timeout: 10)
        assertNoText("unencrypted", settle: 2.0)
    }

    // MARK: - skip-download-confirmation

    func testDownloadConfirmationSkippedForMarkedDomain() {
        cleanFixtureFiles()
        app.openInCurrentTab("\(server.baseURL)/")
        assertText("home-root-marker")
        app.runCommand("domain skip-download-confirmation on")
        assertText("skip-download-confirmation=on")

        app.openInCurrentTab("\(server.baseURL)/download")
        assertText("Downloaded: e2e-fixture.bin", timeout: 10)

        let file = downloadsDir.appendingPathComponent("e2e-fixture.bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "downloaded file missing")
    }

    // MARK: - mute-audio

    func testAutoMuteForMarkedDomain() {
        app.openInCurrentTab("\(server.baseURL)/")
        assertText("home-root-marker")
        app.runCommand("domain mute-audio on")
        assertText("mute-audio=on")

        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("alpha-marker")
        assertText("Muted (domain setting)")
    }

    // MARK: - persistence

    func testSettingsPersistAcrossRelaunch() throws {
        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")
        app.runCommand("domain popups-require-confirmation on")
        assertText("popups-require-confirmation=on")

        app.terminate()
        app = VimzenDriver(testDir: testDir)
        try app.launch()
        app.focus()
        assertExactText("NORMAL", timeout: 15)

        app.openInCurrentTab("\(server.baseURL)/popup")
        assertText("popup-opener-marker")

        XCTAssertTrue(app.clickWebElement("window-open-btn"), "window-open button not found on page")
        assertText("Allow popup to")
        app.sendKeys([.code(VimzenDriver.kReturn)])
        assertNoServerHit("/popup-target", settle: 2.0)
        assertTabCount(1)
    }
}
