import XCTest

/// Gesture-level verification for the turn-activity and plan surfaces.
///
/// **Why these exist as UI tests.** Both behaviours below are *tap and scroll*
/// behaviours, and both were previously checked by driving the Simulator with
/// synthetic host mouse events. That approach is unreliable: mid-session the
/// window stops receiving synthetic clicks entirely (mouse *moves* still work,
/// which makes it look like the app hung), and it survives relaunching
/// Simulator.app. XCUITest runs inside the simulator and needs no host mouse
/// events, so it is immune to that failure and can run unattended.
///
/// The fixtures come from the debug gallery rather than a live server: these
/// assertions are about disclosure mechanics, which must hold regardless of
/// whose data is on screen, and a server-backed test would be gated on
/// credentials and network state.
final class ActivityDisclosureUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchGallery(
        page: Int,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--surface-gallery", "--surface-gallery-page", "\(page)"]
            + additionalArguments
        app.launch()
        return app
    }

    /// The reported bug: opening the merged card and then tapping the thinking
    /// pill inside it. Asserts the disclosure actually round-trips — the body
    /// becomes exposed on expand and hidden on collapse — while sampling the
    /// sibling geometry through the animation interval that originally glitched.
    ///
    /// Page 22 mounts the fold and its sections with production defaults, and
    /// drives the fold open on a timer; the *thinking* tap is what this test
    /// performs itself.
    func testThinkingSectionInsideMergedCardExpandsAndCollapses() {
        let app = launchGallery(page: 22)
        assertThinkingDisclosureKeepsSiblingOrder(in: app)
    }

    /// The retained renderer must use the final card width even when Dynamic
    /// Type makes the thought substantially taller before disclosure.
    func testThinkingSectionExpansionAtAccessibilityTextSize() {
        let app = launchGallery(
            page: 22,
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        assertThinkingDisclosureKeepsSiblingOrder(in: app)
    }

    private func assertThinkingDisclosureKeepsSiblingOrder(in app: XCUIApplication) {

        let thinkingHeader = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-header").firstMatch
        XCTAssertTrue(
            thinkingHeader.waitForExistence(timeout: 15),
            "The merged card should reveal a thinking section."
        )

        let body = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-body").firstMatch

        // The section starts collapsed (a pill) — this is the regression that
        // produced the markdown-pops-in-at-full-height artifact when it did not.
        XCTAssertFalse(body.exists, "The thinking section should start collapsed.")

        let toolsHeader = app.descendants(matching: .any)
            .matching(identifier: "activity.tools-header").firstMatch
        XCTAssertTrue(
            toolsHeader.waitForExistence(timeout: 5),
            "The tools sibling should remain mounted while Thought expands."
        )

        thinkingHeader.tap()

        // The field failure lasted only ~0.5s: Thought disappeared and the
        // tools sibling crossed through the Activity header before the final
        // model geometry settled. Sample throughout that entire interval, not
        // merely after `waitForExistence`, so a transient accessibility-layout
        // regression fails here. Frame-video comparison remains the compositor-
        // level acceptance gate because XCUI does not expose presentation layers.
        let disclosureDeadline = Date().addingTimeInterval(0.75)
        repeat {
            XCTAssertTrue(thinkingHeader.exists, "Thought must stay mounted throughout expansion.")
            XCTAssertTrue(toolsHeader.exists, "Tools must stay mounted throughout Thought expansion.")
            XCTAssertGreaterThanOrEqual(
                toolsHeader.frame.minY,
                thinkingHeader.frame.maxY - 0.5,
                "Tools must never cross above the Thought header during expansion."
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < disclosureDeadline

        XCTAssertTrue(
            body.waitForExistence(timeout: 5),
            "Tapping the thinking pill should expose the pre-mounted thought body."
        )

        thinkingHeader.tap()
        // Accessibility hides the retained renderer once the collapse finishes.
        XCTAssertTrue(
            body.waitForNonExistence(timeout: 5),
            "Tapping again should hide the thought body."
        )
    }

    /// The 68-tool card: the expanded tool list must be bounded and scrollable
    /// rather than rendering every row inline. Page 21 is the 68-tool fixture.
    func testLongToolListIsBoundedAndScrollable() {
        let app = launchGallery(page: 21)

        let toolsHeader = app.descendants(matching: .any)
            .matching(identifier: "activity.tools-header").firstMatch
        XCTAssertTrue(
            toolsHeader.waitForExistence(timeout: 15),
            "The 68-tool fixture should render a tool block."
        )
        toolsHeader.tap()

        let runs = app.descendants(matching: .any)
            .matching(identifier: "activity.tool-runs-scroll").firstMatch
        XCTAssertTrue(
            runs.waitForExistence(timeout: 5),
            "Expanding a 68-tool block should produce a scrollable list."
        )

        // Bounded: the window must be a fraction of the screen, not 68 rows of
        // inline content. This is the assertion that fails if the cap regresses.
        let screenHeight = app.windows.firstMatch.frame.height
        XCTAssertLessThan(
            runs.frame.height,
            screenHeight * 0.6,
            "The tool list should be capped, not rendered inline at full length."
        )

        // Scrollable: a real swipe inside the window must move its content.
        // Comparing a row's position before/after proves the gesture landed.
        let firstRowBefore = runs.descendants(matching: .any).allElementsBoundByIndex.first?.frame.origin.y
        runs.swipeUp()
        let firstRowAfter = runs.descendants(matching: .any).allElementsBoundByIndex.first?.frame.origin.y
        if let before = firstRowBefore, let after = firstRowAfter {
            XCTAssertNotEqual(before, after, accuracy: 0.5, "The capped list should scroll.")
        }
    }

    /// The plan card reported as cut off, unscrollable, and impossible to
    /// close. Page 23 reproduces the field conditions: a five-step plan opening
    /// expanded with no prior measurement while the keyboard is up.
    func testPlanCardStaysBoundedAndCollapsesOnRowTap() {
        let app = launchGallery(page: 23)

        let rows = app.descendants(matching: .any)
            .matching(identifier: "plan.rows-scroll").firstMatch
        XCTAssertTrue(
            rows.waitForExistence(timeout: 15),
            "The live plan fixture should open expanded."
        )

        // Bounded above the composer: the card must not run off the top of the
        // screen (the original overflow) nor extend below the screen's bottom.
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(
            rows.frame.minY, 0,
            "The plan checklist should not overflow past the top of the screen."
        )
        XCTAssertLessThanOrEqual(
            rows.frame.maxY, window.maxY,
            "The plan checklist should not extend below the screen."
        )

        // Tapping the rows area collapses the card — the header used to be the
        // only way out, and it was the part that got clipped away.
        rows.tap()
        XCTAssertTrue(
            rows.waitForNonExistence(timeout: 5),
            "Tapping the plan rows should collapse the card."
        )
    }
}
