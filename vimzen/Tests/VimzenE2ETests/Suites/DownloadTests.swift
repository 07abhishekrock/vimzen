import XCTest

/// Downloads (with Y/n confirm) and PDF export.
/// These touch the real ~/Downloads; each test pre-cleans and post-cleans its files.
final class DownloadTests: E2ETestCase {

    private var downloadsDir: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    private func cleanFixtureFiles() {
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(atPath: downloadsDir.path) {
            for item in items where item.hasPrefix("e2e-fixture") || item.hasPrefix("E2EPDFPAGE") {
                try? fm.removeItem(at: downloadsDir.appendingPathComponent(item))
            }
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        cleanFixtureFiles()
    }

    override func tearDownWithError() throws {
        cleanFixtureFiles()
        try super.tearDownWithError()
    }

    func testDownloadAccept() {
        app.openInCurrentTab("\(server.baseURL)/download")

        assertText("Download e2e-fixture.bin")
        assertText("[Y/n]") // default Yes
        app.sendKeys([.code(VimzenDriver.kReturn)])

        assertText("Downloaded: e2e-fixture.bin", timeout: 10)

        let file = downloadsDir.appendingPathComponent("e2e-fixture.bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "downloaded file missing")
        XCTAssertEqual(try? String(contentsOf: file, encoding: .utf8), "E2E-FIXTURE-PAYLOAD")
    }

    func testDownloadDecline() {
        app.openInCurrentTab("\(server.baseURL)/download")

        assertText("Download e2e-fixture.bin")
        app.tap("n")

        XCTAssertTrue(app.waitForTextToDisappear("Download e2e-fixture.bin"))
        assertNoText("Downloaded:", settle: 2.0)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: downloadsDir.appendingPathComponent("e2e-fixture.bin").path),
            "declined download must not write a file"
        )
    }

    func testPrintPdf() {
        app.openInCurrentTab("\(server.baseURL)/pdfpage")
        assertText("pdf-marker")

        app.runCommand("printpdf")
        assertText("Saved PDF: E2EPDFPAGE.pdf", timeout: 15)

        let file = downloadsDir.appendingPathComponent("E2EPDFPAGE.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "exported PDF missing")
        if let data = try? Data(contentsOf: file) {
            XCTAssertTrue(data.starts(with: Data("%PDF".utf8)), "exported file is not a PDF")
        }
    }
}
