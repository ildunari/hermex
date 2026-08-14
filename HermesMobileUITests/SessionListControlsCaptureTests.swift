import XCTest

/// Screenshot capture for the session-list controls.
///
/// Runs as a UI test because the lab's launch argument only reliably reaches
/// the app through `XCUIApplication.launchArguments`; a plain `simctl launch`
/// restores the previous chat instead. Attachments land in the `.xcresult`.
final class SessionListControlsCaptureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCaptureSessionControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--session-controls-lab"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["lab.visibleRows"].waitForExistence(timeout: 15),
            "lab did not mount"
        )
        attach(app, name: "01-default-with-badge")

        app.buttons["sessionList.sortMenu"].tap()
        XCTAssertTrue(app.buttons["Status"].waitForExistence(timeout: 5), "menu did not open")
        attach(app, name: "02-sort-menu-open")

        app.buttons["Status"].tap()
        XCTAssertTrue(
            app.staticTexts["lab.sectionIDs"].waitForExistence(timeout: 5),
            "sections did not render"
        )
        attach(app, name: "03-grouped-by-status")

        app.buttons["sessionList.inboxToggle"].tap()
        XCTAssertEqual(app.staticTexts["lab.inboxMode"].label, "inbox")
        attach(app, name: "04-inbox-cards")
    }
}
