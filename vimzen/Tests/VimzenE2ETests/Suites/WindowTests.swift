import XCTest

/// Window chrome: double-click header zoom/restore and smooth drag.
final class WindowTests: E2ETestCase {

    func testDoubleClickHeaderZoomsAndRestores() {
        guard let initial = app.waitForWindow({ $0.width > 400 }, timeout: 5) else {
            XCTFail("window not found")
            return
        }
        XCTAssertEqual(initial.width, 1100, accuracy: 5, "test mode must start at the deterministic 1100x700 frame")

        app.clickHeader(doubleClick: true)
        // The zoom is animated — wait for the frame to settle at full size before
        // sending the second double-click, or its first click lands mid-animation
        // and starts a drag instead of toggling the zoom
        guard let zoomed = app.waitForWindowToSettle(), zoomed.width > 1300 else {
            XCTFail("window did not zoom after header double-click")
            return
        }

        app.clickHeader(doubleClick: true)
        let restored = app.waitForWindow({ abs($0.width - initial.width) < 40 }, timeout: 10)
        XCTAssertNotNil(restored, "window did not restore after second header double-click")
    }

    func testDragHeaderMovesWindow() {
        guard let before = app.waitForWindow({ $0.width > 400 }, timeout: 5) else {
            XCTFail("window not found")
            return
        }

        app.dragHeader(dx: 140, dy: 110)

        // The window can lag the pointer slightly on the vertical axis; require a
        // clear, approximately-correct move in both directions
        let moved = app.waitForWindow({
            abs($0.origin.x - (before.origin.x + 140)) < 50 &&
            ($0.origin.y - before.origin.y) > 50 &&
            abs($0.origin.y - (before.origin.y + 110)) < 80
        }, timeout: 10)
        XCTAssertNotNil(moved, "window did not follow header drag")
    }
}
