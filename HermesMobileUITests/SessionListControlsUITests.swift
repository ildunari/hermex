import XCTest

/// Gesture-level verification for the session-list bell and sort menu.
///
/// These are tap behaviours on a `Menu`, which cannot be exercised from unit
/// tests, and driving the Simulator with synthetic host clicks is unreliable on
/// this machine (host clicks silently stop being delivered mid-session).
/// XCUITest runs inside the simulator, so it is immune to that failure.
///
/// The fixtures come from `--session-controls-lab` rather than a live server:
/// the assertions are about filter/group mechanics, which must hold regardless
/// of whose sessions are on screen, and a server-backed test would be gated on
/// credentials and network state. The lab mounts the production controls and
/// the production filter/group functions, so a pass means shipping code works.
final class SessionListControlsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchLab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--session-controls-lab"]
        app.launch()
        return app
    }

    /// Newline-free roster of the rows currently rendered, in order.
    private func visibleRows(_ app: XCUIApplication) -> String {
        let label = app.staticTexts["lab.visibleRows"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "lab did not mount")
        return label.label
    }

    private func sectionIDs(_ app: XCUIApplication) -> String {
        app.staticTexts["lab.sectionIDs"].label
    }

    /// Opens the sort menu and taps one item by title.
    ///
    /// Every menu title is unique by design — grouping options are nouns
    /// ("Status") and ordering options are phrased as orderings ("Urgency") —
    /// so an exact match is unambiguous. A duplicate title would make this
    /// throw, which is the intended signal that the menu got ambiguous again.
    private func chooseMenuItem(_ title: String, in app: XCUIApplication) {
        let sortMenu = app.buttons["sessionList.sortMenu"]
        XCTAssertTrue(sortMenu.waitForExistence(timeout: 5), "sort control missing")
        sortMenu.tap()

        let matches = app.buttons.matching(identifier: title)
        let item = matches.element(boundBy: 0)
        XCTAssertTrue(item.waitForExistence(timeout: 5), "menu item '\(title)' missing")
        XCTAssertEqual(
            matches.count,
            1,
            "menu title '\(title)' is ambiguous (\(matches.count) matches)"
        )
        item.tap()
    }

    // MARK: - Inbox

    func testInboxToggleSwitchesViewModeWithoutFilteringRows() {
        let app = launchLab()
        let allRows = visibleRows(app)
        XCTAssertTrue(allRows.contains("approval"), "fixture roster missing: \(allRows)")
        XCTAssertTrue(allRows.contains("idle"), "fixture roster missing: \(allRows)")

        let inbox = app.buttons["sessionList.inboxToggle"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 5), "inbox control missing")
        XCTAssertTrue(inbox.isEnabled, "inbox must stay tappable with no pending work")
        XCTAssertEqual(app.staticTexts["lab.inboxMode"].label, "list")

        inbox.tap()
        XCTAssertEqual(app.staticTexts["lab.inboxMode"].label, "inbox")
        XCTAssertEqual(visibleRows(app), allRows, "inbox is a render mode, not a filter")

        inbox.tap()
        XCTAssertEqual(app.staticTexts["lab.inboxMode"].label, "list")
        XCTAssertEqual(visibleRows(app), allRows, "second tap should leave the list intact")
    }

    func testAllProfilesMenuItemTogglesScope() {
        let app = launchLab()
        XCTAssertEqual(app.staticTexts["lab.profileScope"].label, "active-profile")
        chooseMenuItem("All profiles", in: app)
        XCTAssertEqual(app.staticTexts["lab.profileScope"].label, "all-profiles")
        chooseMenuItem("All profiles", in: app)
        XCTAssertEqual(app.staticTexts["lab.profileScope"].label, "active-profile")
    }

    // MARK: - Sort menu

    func testStatusGroupingOrdersNeedsInputFirst() {
        let app = launchLab()
        chooseMenuItem("Status", in: app)

        let ids = sectionIDs(app)
        XCTAssertTrue(
            ids.hasPrefix("needs-input"),
            "needs-input should lead the sections, got '\(ids)'"
        )
        XCTAssertTrue(ids.contains("working"), "missing working section: \(ids)")
        XCTAssertTrue(ids.contains("idle"), "missing idle section: \(ids)")
    }

    func testProjectGroupingBucketsByProject() {
        let app = launchLab()
        chooseMenuItem("Project", in: app)

        let ids = sectionIDs(app)
        XCTAssertTrue(ids.contains("hermex"), "missing hermex bucket: \(ids)")
        XCTAssertTrue(ids.contains("other"), "missing other bucket: \(ids)")
    }

    func testArchivedToggleRevealsArchivedRow() {
        let app = launchLab()
        XCTAssertFalse(
            visibleRows(app).contains("archived"),
            "archived row should be hidden by default"
        )

        chooseMenuItem("Archived", in: app)
        XCTAssertTrue(
            visibleRows(app).contains("archived"),
            "archived row should appear once the toggle is on"
        )
    }

    func testWorkingFilterKeepsOnlyStreamingSessions() {
        let app = launchLab()
        chooseMenuItem("Working", in: app)

        let rows = visibleRows(app)
        XCTAssertTrue(rows.contains("working"), "streaming row hidden: \(rows)")
        XCTAssertFalse(rows.contains("idle"), "idle row should be filtered out: \(rows)")
        XCTAssertFalse(rows.contains("approval"), "approval row should be filtered out: \(rows)")
    }

    func testResetReturnsToTheDefaultView() {
        let app = launchLab()
        let original = visibleRows(app)

        chooseMenuItem("Working", in: app)
        XCTAssertNotEqual(visibleRows(app), original, "filter did not change the list")

        chooseMenuItem("Reset to defaults", in: app)
        XCTAssertEqual(visibleRows(app), original, "reset did not restore the default view")
    }
}
