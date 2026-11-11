import XCTest

/// Profile workspaces (Model B): creation, switching, tab scoping,
/// cookie/storage isolation, tab transfer, alternate profile.
final class ProfileTests: E2ETestCase {

    func testCreateAndSwitchProfile() {
        app.runCommand("p new e2ework")

        assertText("Profile: e2ework")
        assertText("[e2ew]")
        assertTabCount(1) // new profile starts with a fresh scratchpad
    }

    func testSwitchProfileByBadge() {
        app.runCommand("p new e2ework")
        assertText("[e2ew]")

        app.runCommand("p pers")
        assertText("[pers]")
        assertText("Profile: Personal")
    }

    func testTabsScopedPerProfile() {
        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")
        app.openInNewTab("\(server.baseURL)/beta")
        assertTabCount(2)

        app.runCommand("p new zz")
        assertTabCount(1)

        app.runCommand("p pers")
        assertTabCount(2)
        assertText("Beta Page") // pers profile's active tab is restored
    }

    func testCookieIsolationBetweenProfiles() {
        app.openInCurrentTab("\(server.baseURL)/set-cookie")
        assertText("cookie-set-marker")
        app.openInCurrentTab("\(server.baseURL)/echo-cookie")
        assertText("cookies:[e2e_token=present]")

        app.runCommand("p new zz")
        assertText("[zz]")
        app.openInCurrentTab("\(server.baseURL)/echo-cookie")
        // Same host, different data store → no cookie leaks across profiles
        assertText("cookies:[]")
    }

    func testMoveTabToProfile() {
        app.runCommand("p new zz")
        assertText("[zz]")
        app.runCommand("p pers")
        assertText("[pers]")

        app.openInCurrentTab("\(server.baseURL)/alpha")
        assertText("Alpha Page")

        app.runCommand("send zz")
        assertText("Moved to zz")
        assertText("[zz]")
        assertText("Alpha Page") // the moved tab is active in the target profile
        assertTabCount(2) // zz's creation-time scratchpad + the moved tab
    }

    func testAlternateProfileSwitch() {
        app.runCommand("p new zz")
        assertText("[zz]")

        app.runCommand("p#")
        assertText("[pers]")
    }

    func testProfilePickerCancelKeepsProfile() {
        app.sendKeys([.type("g"), .type("p")], interDelay: 0.12) // gp
        assertMode("COMMAND")
        assertExactText("PROFILE")

        app.escape()
        assertMode("NORMAL")
        assertText("[pers]")
    }
}
