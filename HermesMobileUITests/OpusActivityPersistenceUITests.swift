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

/// In-simulator navigation coverage for the session-list refresh work.
///
/// These drive real taps (enter a chat, come back) because that is the trigger
/// under test — `SessionListNewChatReturn.run` fires on a navigation
/// destination change, which no unit test can produce. Host-side synthetic
/// clicks are unreliable on this machine, so the taps run inside the simulator
/// via XCUITest.
///
/// The server is a scriptable stand-in (`HERMEX_MOCK_SERVER`, default the
/// tailnet mock) whose request log the harness reads to count `/api/sessions`
/// fetches. Assertions here are about *fetch counts and row correctness on
/// return*, which hold for any server.
final class SessionListReturnRefreshUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // Restore the fixture rows so these tests are order-independent: an
        // earlier test renames a row, and a hardcoded title would then miss.
        control("/__ctl/reset_state")
    }

    private var mockServer: String {
        ProcessInfo.processInfo.environment["HERMEX_MOCK_SERVER"]
            ?? "http://100.69.228.58:8799"
    }

    /// Calls the mock's control plane. Returns the body, or nil on failure.
    @discardableResult
    private func control(_ path: String, body: String? = nil) -> String? {
        guard let url = URL(string: mockServer + path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        if let body { request.httpBody = Data(body.utf8) }

        var result: String?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = data.flatMap { String(data: $0, encoding: .utf8) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 15)
        return result
    }

    /// Number of times `/api/sessions` has been requested since the last reset.
    private func sessionFetchCount() -> Int {
        guard let url = URL(string: mockServer + "/__ctl/counts") else { return -1 }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        var count = -1
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { done.signal() }
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            count = object["/api/sessions"] as? Int ?? 0
        }.resume()
        _ = done.wait(timeout: .now() + 15)
        return count
    }

    private func launchConnectedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--auto-connect-server", mockServer]
        app.launch()
        return app
    }

    /// Waits for the session list itself, not merely for the app to draw.
    private func waitForSessionList(_ app: XCUIApplication) {
        let anyRow = app.staticTexts["Bravo session"]
        XCTAssertTrue(anyRow.waitForExistence(timeout: 45), "Session list never populated.")
    }

    /// Scenario B: leaving a chat reconciles the list, and costs exactly one fetch.
    func testReturningFromChatRefreshesOnceAndShowsUpdatedRow() throws {
        let app = launchConnectedApp()
        waitForSessionList(app)

        let row = app.staticTexts["Bravo session"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Target row missing.")
        row.tap()

        // Confirm we actually entered a chat before judging the return.
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 30), "Never entered the chat.")

        // Let the staleness window lapse so the return refresh is not gated,
        // then rename server-side: only a live reconcile can surface this.
        Thread.sleep(forTimeInterval: 6)
        let reconciledTitle = "Reconciled-\(Int(Date().timeIntervalSince1970))"
        control("/__ctl/session/sess-bravo/title", body: reconciledTitle)
        control("/__ctl/reset_counts")

        backButton.tap()

        // Back-navigation needs a polling wait, never an immediate `.exists`.
        // The renamed row can only appear via a live reconcile fetch.
        let renamed = app.staticTexts[reconciledTitle]
        var appeared = false
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if renamed.exists { appeared = true; break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(appeared, "Return from chat did not reconcile the row against the server.")

        // Let any duplicate triggers land before counting.
        Thread.sleep(forTimeInterval: 4)
        let fetches = sessionFetchCount()
        XCTAssertEqual(fetches, 1, "Return from chat should cost exactly one /api/sessions fetch, got \(fetches).")
    }

    /// Scenario F: hammering enter/exit must not produce a fetch storm.
    ///
    /// Uses the static fixture (no streaming row): a row polling once a second
    /// keeps re-rendering the list, which slows XCUITest element resolution so
    /// much that "rapid" navigation drifts past the staleness window and the
    /// fetch count stops measuring burst collapsing at all.
    func testRapidEnterExitDoesNotStormTheServer() throws {
        control("/__ctl/reset_state/static")

        let app = launchConnectedApp()
        waitForSessionList(app)

        // Zero the counter only after the launch fetch has landed, so the count
        // reflects the navigation burst alone.
        Thread.sleep(forTimeInterval: 6)
        control("/__ctl/reset_counts")

        let burstStart = Date()
        var completedRoundTrips = 0

        for iteration in 0..<5 {
            let row = app.staticTexts["Bravo session"]
            var rowReady = false
            // 60s, not 20s: under build/machine load XCUITest element resolution
            // can take minutes; a tight deadline fails the harness, not the app.
            // The fetch-count assertions below are time-normalized, so a slow
            // burst still measures collapsing honestly.
            let rowDeadline = Date().addingTimeInterval(60)
            while Date() < rowDeadline {
                if row.exists { rowReady = true; break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
            XCTAssertTrue(rowReady, "Row missing on iteration \(iteration).")
            row.tap()

            let back = app.navigationBars.buttons.firstMatch
            var backReady = false
            let backDeadline = Date().addingTimeInterval(60)
            while Date() < backDeadline {
                if back.exists { backReady = true; break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
            XCTAssertTrue(backReady, "Never entered chat on iteration \(iteration).")
            back.tap()
            completedRoundTrips += 1
        }

        let burstDuration = Date().timeIntervalSince(burstStart)
        Thread.sleep(forTimeInterval: 4)
        let fetches = sessionFetchCount()

        // The gate is time-based, so the honest bound is one fetch per staleness
        // window that actually elapsed (plus one for the trailing settle), not a
        // fixed constant: if XCUITest is slow enough that the returns span
        // several windows, refetching is correct behaviour rather than a storm.
        let windows = Int(burstDuration / 5.0) + 2
        XCTAssertLessThanOrEqual(
            fetches,
            windows,
            "Fetch storm: \(fetches) /api/sessions calls for \(completedRoundTrips) returns "
                + "over \(String(format: "%.1f", burstDuration))s."
        )
        // The point of the change: returns must cost far less than one fetch each.
        XCTAssertLessThan(fetches, completedRoundTrips, "Returns did not collapse into shared fetches.")
        XCTAssertTrue(app.staticTexts["Bravo session"].waitForExistence(timeout: 20), "List broke after rapid navigation.")
    }
}
