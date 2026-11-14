import XCTest

/// Per-tab, session-only userscript kill switch (:userscripts off|on).
final class UserScriptsTests: E2ETestCase {

    /// Scripts are attached at tab init, so a script dropped into the isolated
    /// test dir is picked up by the next created tab (no app restart needed).
    private func writeMarkerScript() throws {
        let scriptsDir = testDir.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        let marker = """
        (function() {
            var el = document.createElement('p');
            el.textContent = 'userscript-ran-marker';
            document.body.appendChild(el);
        })();
        """
        try marker.write(to: scriptsDir.appendingPathComponent("e2e_marker.js"), atomically: true, encoding: .utf8)
    }

    func testUserScriptsTogglePerTab() throws {
        try writeMarkerScript()

        app.openInNewTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        assertText("userscript-ran-marker")

        server.clearLog()
        app.runCommand("userscripts off")
        assertText("Userscripts: OFF (this tab)")
        assertServerHit("/alpha") // disabling reloads the page (UCC changes apply on next load only)
        XCTAssertTrue(app.waitForTextToDisappear("userscript-ran-marker"))
        assertText("Alpha Page") // the page itself still loads fine

        server.clearLog()
        app.runCommand("userscripts on")
        assertText("Userscripts: ON")
        assertServerHit("/alpha") // re-enabling reloads again
        assertText("userscript-ran-marker")
    }
}
