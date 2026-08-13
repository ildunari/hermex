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

        let initialHeaderMinY = thinkingHeader.frame.minY
        thinkingHeader.tap()

        // Sample beyond both the ~0.5s visual disclosure and the 1.25s
        // preservation window. This catches a late SwiftUI offset correction
        // that would otherwise fire only after the position lock expired.
        // Frame-video comparison remains the compositor-level acceptance gate
        // because XCUI does not expose presentation layers.
        let disclosureDeadline = Date().addingTimeInterval(1.5)
        repeat {
            XCTAssertTrue(thinkingHeader.exists, "Thought must stay mounted throughout expansion.")
            XCTAssertTrue(toolsHeader.exists, "Tools must stay mounted throughout Thought expansion.")
            XCTAssertEqual(
                thinkingHeader.frame.minY,
                initialHeaderMinY,
                // The pill-to-card chrome itself has a designed 7pt inset
                // exchange; anything beyond that is viewport movement.
                accuracy: 8,
                "Thought must open in place without moving the reader to a different viewport position."
            )
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

        body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        // Accessibility hides the retained renderer once the collapse finishes.
        XCTAssertTrue(
            body.waitForNonExistence(timeout: 5),
            "Tapping the expanded thought output should collapse it without returning to the header."
        )
    }

    func testCompletedThinkingOutputUsesCompactPreviewAndDedicatedReader() {
        let app = launchGallery(page: 24)
        assertLongThinkingOutputUsesCompactPreviewAndDedicatedReader(in: app)
    }

    func testLiveThinkingOutputUsesCompactPreviewAndDedicatedReader() {
        let app = launchGallery(page: 25)
        assertLongThinkingOutputUsesCompactPreviewAndDedicatedReader(in: app)
    }

    func testThinkingOutputBoundsAtAccessibilityTextSize() {
        let app = launchGallery(
            page: 24,
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        assertLongThinkingOutputUsesCompactPreviewAndDedicatedReader(in: app)
    }

    func testLiveThinkingPreviewOpensDownwardWithoutPushingTranscript() {
        let app = launchGallery(page: 26)
        let header = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-header").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        let body = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-body").firstMatch
        XCTAssertFalse(body.exists)
        let followingContent = app.descendants(matching: .any)
            .matching(identifier: "gallery.thinking-following-content").firstMatch
        XCTAssertTrue(followingContent.waitForExistence(timeout: 5))

        let initialHeaderY = header.frame.minY
        let initialFollowingY = followingContent.frame.minY
        header.tap()

        let deadline = Date().addingTimeInterval(1.5)
        repeat {
            XCTAssertEqual(
                header.frame.minY,
                initialHeaderY,
                accuracy: 8,
                "Explicit live Thought expansion must not let bottom-follow push its header upward."
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < deadline

        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            followingContent.frame.minY,
            initialFollowingY,
            "The preview should grow downward and move following content, not move its own header upward."
        )

        let expandedHeaderY = header.frame.minY
        body.swipeUp()
        XCTAssertLessThan(
            header.frame.minY,
            expandedHeaderY - 0.5,
            "A drag that begins inside the non-scrolling Thought preview must scroll the enclosing transcript."
        )
    }

    private func assertLongThinkingOutputUsesCompactPreviewAndDedicatedReader(in app: XCUIApplication) {
        let body = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 15), "The long Thought should open expanded.")
        let header = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-header").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))

        let screenHeight = app.windows.firstMatch.frame.height
        XCTAssertLessThanOrEqual(
            body.frame.maxY - header.frame.minY,
            screenHeight * 0.42,
            "The complete inline Thought preview should occupy about 40% or less of the viewport."
        )

        let firstText = body.descendants(matching: .staticText).firstMatch
        XCTAssertTrue(firstText.waitForExistence(timeout: 5))
        let initialRelativeTextY = firstText.frame.minY - body.frame.minY
        body.swipeUp()
        XCTAssertEqual(
            firstText.frame.minY - body.frame.minY,
            initialRelativeTextY,
            accuracy: 0.5,
            "Dragging the preview must move the transcript, not create a competing nested scroll."
        )

        let readFull = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-read-full").firstMatch
        XCTAssertTrue(readFull.waitForExistence(timeout: 5))
        readFull.tap()

        let reader = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-full-reader").firstMatch
        XCTAssertTrue(reader.waitForExistence(timeout: 5), "Long output should open in a dedicated reader.")
        let readerText = reader.descendants(matching: .staticText).firstMatch
        XCTAssertTrue(readerText.waitForExistence(timeout: 5))
        let readerTextY = readerText.frame.minY
        reader.swipeUp()
        XCTAssertNotEqual(
            readerText.frame.minY,
            readerTextY,
            accuracy: 0.5,
            "The dedicated Thought reader should own vertical scrolling."
        )
        app.buttons["Close"].tap()
        XCTAssertTrue(reader.waitForNonExistence(timeout: 5))

        body.tap()
        XCTAssertTrue(
            body.waitForNonExistence(timeout: 5),
            "Tapping anywhere in the expanded Thinking output should collapse it."
        )
    }

    /// The 68-tool card: the expanded tool list must be bounded and scrollable
    /// rather than rendering every row inline. Page 21 is the 68-tool fixture.
    func testLongToolListIsBoundedAndScrollable() {
        let app = launchGallery(page: 21)
        let runs = assertLongToolListColdDisclosure(in: app)

        // Bounded: the normal-size window must be a fraction of the screen,
        // not 68 rows of inline content.
        let screenHeight = app.windows.firstMatch.frame.height
        XCTAssertLessThan(
            runs.frame.height,
            screenHeight * 0.6,
            "The tool list should be capped, not rendered inline at full length."
        )

        // Scrollable: a real swipe inside the window must move its content.
        let firstRowBefore = runs.descendants(matching: .any).allElementsBoundByIndex.first?.frame.origin.y
        runs.swipeUp()
        let firstRowAfter = runs.descendants(matching: .any).allElementsBoundByIndex.first?.frame.origin.y
        if let before = firstRowBefore, let after = firstRowAfter {
            XCTAssertNotEqual(before, after, accuracy: 0.5, "The capped list should scroll.")
        }
    }

    func testLongToolListColdDisclosureAtAccessibilityTextSize() {
        let app = launchGallery(
            page: 21,
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        let runs = assertLongToolListColdDisclosure(in: app)
        XCTAssertLessThan(
            runs.frame.height,
            app.windows.firstMatch.frame.height,
            "Accessibility rows may be taller, but the tool window must remain screen-bounded."
        )
    }

    private func assertLongToolListColdDisclosure(in app: XCUIApplication) -> XCUIElement {

        let toolsHeader = app.descendants(matching: .any)
            .matching(identifier: "activity.tools-header").firstMatch
        XCTAssertTrue(
            toolsHeader.waitForExistence(timeout: 15),
            "The 68-tool fixture should render a tool block."
        )
        let thinkingHeader = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-header").firstMatch
        XCTAssertTrue(
            thinkingHeader.waitForExistence(timeout: 5),
            "The Thought sibling should remain mounted while tools expand."
        )

        let initialHeaderMinY = toolsHeader.frame.minY
        toolsHeader.tap()

        // This is intentionally the first open on a freshly mounted 68-tool
        // block. The historical bug unmounted the header, collapsed the outer
        // Activity container, then inserted an empty body before rows appeared.
        let firstOpenDeadline = Date().addingTimeInterval(1.5)
        repeat {
            XCTAssertTrue(toolsHeader.exists, "Ran tools must stay mounted on its cold first open.")
            XCTAssertTrue(thinkingHeader.exists, "Thought must stay mounted while tools open.")
            XCTAssertEqual(
                toolsHeader.frame.minY,
                initialHeaderMinY,
                accuracy: 8,
                "Ran tools must expand in place without moving the transcript viewport."
            )
            XCTAssertGreaterThanOrEqual(
                toolsHeader.frame.minY,
                thinkingHeader.frame.maxY - 0.5,
                "Ran tools must never cross above the Thought sibling."
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < firstOpenDeadline

        let runs = app.descendants(matching: .any)
            .matching(identifier: "activity.tool-runs-scroll").firstMatch
        XCTAssertTrue(
            runs.waitForExistence(timeout: 5),
            "Expanding a 68-tool block should produce a scrollable list."
        )

        // Warm second open must obey the same geometry after the measured list
        // height has been cached by this retained view instance.
        app.descendants(matching: .any)
            .matching(identifier: "activity.tools-header").firstMatch.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        app.descendants(matching: .any)
            .matching(identifier: "activity.tools-header").firstMatch.tap()
        let secondOpenDeadline = Date().addingTimeInterval(0.75)
        repeat {
            XCTAssertTrue(toolsHeader.exists, "Ran tools must stay mounted on its warm reopen.")
            XCTAssertGreaterThanOrEqual(
                toolsHeader.frame.minY,
                thinkingHeader.frame.maxY - 0.5,
                "Warm reopen must preserve sibling ordering."
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < secondOpenDeadline
        XCTAssertTrue(runs.waitForExistence(timeout: 5))
        return runs
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
