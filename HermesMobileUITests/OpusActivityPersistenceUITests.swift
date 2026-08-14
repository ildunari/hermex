import XCTest

/// Live Opus regression test for provider-neutral activity persistence.
///
/// Opus streams ordinary, unphased prose before tool calls. That provisional
/// assistant bubble must not make the live Thought/Ran Tools surfaces disappear
/// or collapse before the turn actually finishes.
final class OpusActivityPersistenceUITests: XCTestCase {
    private struct LiveServer: Decodable {
        let url: String
        let password: String
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOpusActivityStaysRichUntilTurnFinishes() throws {
        let server = try liveServer()
        let app = XCUIApplication()
        app.launchArguments = [
            "--auto-connect-server", server.url,
            "--auto-connect-password", server.password,
        ]
        app.launch()

        let composer = app.textViews.firstMatch
        if composer.waitForExistence(timeout: 20) {
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "Could not leave the restored session.")
            back.tap()
        }

        let newSession = app.buttons["New Session"]
        XCTAssertTrue(
            newSession.waitForExistence(timeout: 30),
            "Authenticated session list never appeared."
        )
        newSession.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "Fresh-session composer never appeared.")
        try selectOpus(in: app)

        composer.tap()
        composer.typeText(
            "Research the latest official Swift 6.2 guidance for migrating an existing app "
                + "to strict concurrency. Use web search and read at least three independent "
                + "primary sources sequentially. Briefly narrate what you are checking between "
                + "tool calls, compare the recommendations, and finish with a concise cited summary."
        )

        let send = app.buttons["chat.composer.send"].exists
            ? app.buttons["chat.composer.send"]
            : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'send'")).firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "Could not find send.")
        send.tap()

        let stop = app.buttons["Stop response"]
        XCTAssertTrue(stop.waitForExistence(timeout: 20), "Turn never started.")

        let thought = app.descendants(matching: .any)
            .matching(identifier: "activity.thinking-header").firstMatch
        let tools = app.descendants(matching: .any)
            .matching(identifier: "activity.tools-header").firstMatch
        let summary = app.descendants(matching: .any)
            .matching(identifier: "activity.turn-summary-row").firstMatch

        let appearanceDeadline = Date().addingTimeInterval(90)
        while Date() < appearanceDeadline, !thought.exists, !tools.exists, stop.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        }
        XCTAssertTrue(thought.exists || tools.exists, "No rich activity surface appeared.")

        var continuousMissingSamples = 0
        let completionDeadline = Date().addingTimeInterval(240)
        while Date() < completionDeadline, stop.exists {
            let hasRichActivity = thought.exists || tools.exists
            if hasRichActivity {
                continuousMissingSamples = 0
            } else {
                continuousMissingSamples += 1
                XCTAssertLessThan(
                    continuousMissingSamples,
                    5,
                    summary.exists
                        ? "Regression: live Opus activity flattened to summary-only for at least one second mid-turn."
                        : "Regression: live Opus activity disappeared for at least one second mid-turn."
                )
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        }

        XCTAssertFalse(stop.exists, "Opus turn did not finish before the timeout.")
    }

    private func selectOpus(in app: XCUIApplication) throws {
        let composer = app.textViews.firstMatch
        composer.tap()
        composer.typeText("/model claude-opus-5")

        let send = app.buttons["chat.composer.send"].exists
            ? app.buttons["chat.composer.send"]
            : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'send'")).firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "Could not submit /model command.")
        send.tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'opus'")).firstMatch
                .waitForExistence(timeout: 30),
            "Composer did not reflect the Opus selection."
        )
    }

    private func liveServer() throws -> LiveServer {
        let path = ProcessInfo.processInfo.environment["HERMEX_UITEST_CONFIG"]
            ?? "/tmp/hermex-uitest-live-server.json"
        guard let data = FileManager.default.contents(atPath: path) else {
            throw XCTSkip("Missing live-server config at \(path).")
        }
        return try JSONDecoder().decode(LiveServer.self, from: data)
    }
}
