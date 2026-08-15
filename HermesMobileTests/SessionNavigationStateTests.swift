import XCTest
@testable import HermesMobile

final class SessionNavigationStateTests: XCTestCase {
    func testSelectingSessionUpdatesDestinationAndRestorationID() {
        let session = SessionSummary(sessionId: "session-1", title: "One")
        var state = SessionNavigationState()

        state.select(session)

        XCTAssertEqual(state.destination, .session(session))
        XCTAssertEqual(state.selectedSessionID, "session-1")
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testRestoreSelectsStoredSessionWhenItStillExists() {
        let first = SessionSummary(sessionId: "session-1", title: "One")
        let second = SessionSummary(sessionId: "session-2", title: "Two")
        var state = SessionNavigationState(lastSelectedSessionID: "session-2")

        state.restoreIfNeeded(from: [first, second])

        XCTAssertEqual(state.destination, .session(second))
        XCTAssertEqual(state.lastSelectedSessionID, "session-2")
    }

    func testRestoreClearsStoredSelectionWhenSessionNoLongerExists() {
        var state = SessionNavigationState(lastSelectedSessionID: "missing")

        state.restoreIfNeeded(from: [SessionSummary(sessionId: "session-1")])

        XCTAssertNil(state.destination)
        XCTAssertNil(state.lastSelectedSessionID)
    }

    func testRestorePreservesStoredSelectionWhenSessionListIsNotAuthoritative() {
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")

        state.restoreIfNeeded(from: [], clearsMissingSelection: false)

        XCTAssertNil(state.destination)
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testRestoreSkipsWhileDeepLinkIsPendingAndKeepsStoredSelection() {
        let stored = SessionSummary(sessionId: "stored")
        var state = SessionNavigationState(lastSelectedSessionID: "stored")

        state.restoreIfNeeded(from: [stored], pendingDeepLinkedSessionID: "deep-linked")

        XCTAssertNil(state.destination)
        XCTAssertEqual(state.lastSelectedSessionID, "stored")
    }

    func testRestoreSkipsAfterPendingDeepLinkIsConsumedWhileLoadIsInFlight() {
        let stored = SessionSummary(sessionId: "stored")
        var state = SessionNavigationState(lastSelectedSessionID: "stored")

        let deepLinkedSessionID = state.beginDeepLinkedSessionLoad(id: "deep-linked")
        state.restoreIfNeeded(from: [stored], pendingDeepLinkedSessionID: nil)

        XCTAssertEqual(deepLinkedSessionID, "deep-linked")
        XCTAssertNil(state.destination)
        XCTAssertEqual(state.lastSelectedSessionID, "stored")

        state.finishDeepLinkedSessionLoad(id: deepLinkedSessionID)
        state.restoreIfNeeded(from: [stored], pendingDeepLinkedSessionID: nil)

        XCTAssertEqual(state.destination, .session(stored))
    }

    func testRestoreProceedsWhenPendingDeepLinkIDIsBlank() {
        let stored = SessionSummary(sessionId: "stored")
        var state = SessionNavigationState(lastSelectedSessionID: "stored")

        state.restoreIfNeeded(from: [stored], pendingDeepLinkedSessionID: "   ")

        XCTAssertEqual(state.destination, .session(stored))
    }

    func testInitialRefreshStartsBeforeDelayedDeepLinkFinishes() async {
        let recorder = SessionInitialLoadEventRecorder()

        await SessionListInitialLoad.run(
            resolvePendingDeepLink: {
                await recorder.record(.deepLinkStarted)
                try? await Task.sleep(nanoseconds: 50_000_000)
                await recorder.record(.deepLinkFinished)
            },
            refreshSessionsAndActiveProfile: {
                await recorder.record(.refreshStarted)
            }
        )

        let events = await recorder.snapshot()
        guard let refreshIndex = events.firstIndex(of: .refreshStarted),
              let deepLinkFinishIndex = events.firstIndex(of: .deepLinkFinished)
        else {
            return XCTFail("Expected both refresh and deep-link completion events")
        }

        XCTAssertLessThan(refreshIndex, deepLinkFinishIndex)
    }

    func testExplicitNewChatRouteOverridesStoredSelection() {
        let route = PendingNewChatRoute(initialDraft: "Shared draft")
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")
        state.select(route)

        state.restoreIfNeeded(from: [SessionSummary(sessionId: "session-1")])

        XCTAssertEqual(state.destination, .newChat(route))
        XCTAssertEqual(state.lastSelectedSessionID, "session-1")
    }

    func testExplicitSessionRouteOverridesStoredSelection() {
        let stored = SessionSummary(sessionId: "stored")
        let deepLinked = SessionSummary(sessionId: "deep-linked")
        var state = SessionNavigationState(lastSelectedSessionID: "stored")
        state.select(deepLinked)

        state.restoreIfNeeded(from: [stored])

        XCTAssertEqual(state.destination, .session(deepLinked))
        XCTAssertEqual(state.lastSelectedSessionID, "deep-linked")
    }

    func testCreatedSessionRemainsSelectedWhileNewChatRouteOwnsItsDraft() {
        let route = PendingNewChatRoute(initialDraft: "Shared draft")
        let created = SessionSummary(sessionId: "created-session")
        var state = SessionNavigationState()
        state.select(route)
        XCTAssertTrue(state.isCreatingNewChat)

        state.remember(created)

        XCTAssertEqual(state.destination, .newChat(route))
        XCTAssertEqual(state.selectedSessionID, "created-session")
        XCTAssertEqual(state.lastSelectedSessionID, "created-session")
        XCTAssertFalse(state.isCreatingNewChat)
    }

    func testSelectingAnotherNewChatRouteStartsFreshCreationState() {
        let firstRoute = PendingNewChatRoute()
        let secondRoute = PendingNewChatRoute()
        var state = SessionNavigationState()
        state.select(firstRoute)
        state.remember(SessionSummary(sessionId: "created-session"))

        state.select(secondRoute)

        XCTAssertEqual(state.destination, .newChat(secondRoute))
        XCTAssertNil(state.selectedSessionID)
        XCTAssertTrue(state.isCreatingNewChat)
    }

    func testReturningFromContentfulNewChatSuppressesPlaceholdersThenRefreshesSessions() {
        let route = PendingNewChatRoute()
        var state = SessionNavigationState()
        state.select(route)
        state.remember(SessionSummary(sessionId: "created-session"))
        let oldDestination = state.destination
        state.clearDestination()
        var events: [NewChatReturnEvent] = []

        SessionListNewChatReturn.run(
            from: oldDestination,
            to: state.destination,
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { force in events.append(.refreshedSessions(force: force)) }
        )

        // Forced: `createSession` never inserts the row locally, so a gated
        // refresh here loses the session the user just created (review P1-3).
        XCTAssertEqual(events, [.suppressedPlaceholders, .refreshedSessions(force: true)])
    }

    func testReturningFromEmptyNewChatSuppressesPlaceholderThenRefreshesSessions() {
        let route = PendingNewChatRoute()
        var state = SessionNavigationState()
        state.select(route)
        let oldDestination = state.destination
        state.clearDestination()
        var events: [NewChatReturnEvent] = []

        SessionListNewChatReturn.run(
            from: oldDestination,
            to: state.destination,
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { force in events.append(.refreshedSessions(force: force)) }
        )

        // Forced: `createSession` never inserts the row locally, so a gated
        // refresh here loses the session the user just created (review P1-3).
        XCTAssertEqual(events, [.suppressedPlaceholders, .refreshedSessions(force: true)])
    }

    /// P1-3: placeholder suppression runs unconditionally on a newChat return,
    /// but the refresh went through the 5s staleness gate. Load the list, tap
    /// New Chat, send "hi", back out inside 5s and the just-created row was
    /// pruned locally and never refetched — present in no list row and, with the
    /// `.newChat` route gone, unreachable from the sidebar. Only an *unforced*
    /// refresh can be suppressed, so this return must force.
    func testReturningFromNewChatForcesTheRefreshPastTheStalenessGate() {
        var forcedRefreshes: [Bool] = []
        var didSuppress = false

        SessionListNewChatReturn.run(
            from: .newChat(PendingNewChatRoute()),
            to: nil,
            suppressEmptyPlaceholders: { didSuppress = true },
            refreshSessions: { forcedRefreshes.append($0) }
        )

        XCTAssertTrue(didSuppress)
        XCTAssertEqual(
            forcedRefreshes,
            [true],
            "Suppressing placeholders without a guaranteed refetch can lose a brand-new session"
        )
    }

    /// The counterpart: an ordinary chat return has nothing that only exists
    /// server-side, so it stays gated and a burst still costs one fetch.
    func testReturningFromAnExistingChatStaysGated() {
        var forcedRefreshes: [Bool] = []

        SessionListNewChatReturn.run(
            from: .session(SessionSummary(sessionId: "session-1")),
            to: nil,
            suppressEmptyPlaceholders: { XCTFail("newChat-only behavior") },
            refreshSessions: { forcedRefreshes.append($0) }
        )

        XCTAssertEqual(forcedRefreshes, [false])
    }

    /// P2: `didLeaveChat` compared `oldSession.sessionId == newSession.sessionId`,
    /// and `sessionId` is optional — so two *different* malformed rows both
    /// compared `nil == nil` → "same session", suppressing the refresh. `id`
    /// falls back to a title/timestamp composite, so they stay distinct.
    func testSwappingTwoIDLessSessionsIsStillTreatedAsLeavingTheChat() {
        var forcedRefreshes: [Bool] = []

        SessionListNewChatReturn.run(
            from: .session(SessionSummary(sessionId: nil, title: "First malformed row")),
            to: .session(SessionSummary(sessionId: nil, title: "Second malformed row")),
            suppressEmptyPlaceholders: { XCTFail("newChat-only behavior") },
            refreshSessions: { forcedRefreshes.append($0) }
        )

        XCTAssertEqual(
            forcedRefreshes,
            [false],
            "Two ID-less rows are not the same session, so the list must still reconcile"
        )
    }

    /// The same ID-less row reselected is still not a return.
    func testReselectingTheSameIDLessSessionDoesNotRefresh() {
        let session = SessionSummary(sessionId: nil, title: "Malformed", createdAt: 42)
        var didRefresh = false

        SessionListNewChatReturn.run(
            from: .session(session),
            to: .session(session),
            suppressEmptyPlaceholders: { XCTFail("newChat-only behavior") },
            refreshSessions: { _ in didRefresh = true }
        )

        XCTAssertFalse(didRefresh)
    }

    func testReplacingNewChatRouteDoesNotRefreshSessions() {
        let firstRoute = PendingNewChatRoute()
        let secondRoute = PendingNewChatRoute()
        var events: [NewChatReturnEvent] = []

        SessionListNewChatReturn.run(
            from: .newChat(firstRoute),
            to: .newChat(secondRoute),
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { force in events.append(.refreshedSessions(force: force)) }
        )

        XCTAssertTrue(events.isEmpty)
    }

    /// Bug 4: on iPad the detail column swaps straight from one session to
    /// another, never passing through `.newChat`, so the old newChat-only gate
    /// left the sidebar stale.
    func testReturningFromExistingChatRefreshesWithoutSuppressingPlaceholders() {
        let session = SessionSummary(sessionId: "session-1")
        var events: [NewChatReturnEvent] = []

        SessionListNewChatReturn.run(
            from: .session(session),
            to: nil,
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { force in events.append(.refreshedSessions(force: force)) }
        )

        XCTAssertEqual(
            events,
            [.refreshedSessions(force: false)],
            "Placeholder suppression is a newChat-only behavior and must not run here"
        )
    }

    func testSwitchingBetweenTwoExistingChatsRefreshesTheList() {
        var events: [NewChatReturnEvent] = []

        SessionListNewChatReturn.run(
            from: .session(SessionSummary(sessionId: "session-1")),
            to: .session(SessionSummary(sessionId: "session-2")),
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { force in events.append(.refreshedSessions(force: force)) }
        )

        XCTAssertEqual(events, [.refreshedSessions(force: false)])
    }

    func testReselectingTheSameChatDoesNotRefresh() {
        var events: [NewChatReturnEvent] = []
        let session = SessionSummary(sessionId: "session-1", title: "Renamed in place")

        SessionListNewChatReturn.run(
            from: .session(SessionSummary(sessionId: "session-1")),
            to: .session(session),
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { force in events.append(.refreshedSessions(force: force)) }
        )

        XCTAssertTrue(events.isEmpty, "The same session is not a return")
    }

    func testOpeningAChatFromTheListDoesNotRefresh() {
        var events: [NewChatReturnEvent] = []

        SessionListNewChatReturn.run(
            from: nil,
            to: .session(SessionSummary(sessionId: "session-1")),
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { force in events.append(.refreshedSessions(force: force)) }
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testLeavingAUtilityDestinationDoesNotRefresh() {
        var events: [NewChatReturnEvent] = []

        SessionListNewChatReturn.run(
            from: .utility(.settings(nil)),
            to: nil,
            suppressEmptyPlaceholders: { events.append(.suppressedPlaceholders) },
            refreshSessions: { force in events.append(.refreshedSessions(force: force)) }
        )

        XCTAssertTrue(events.isEmpty, "Settings and other utility screens do not change session rows")
    }

    func testRemovingSelectedSessionClearsDestinationAndRestorationID() {
        let session = SessionSummary(sessionId: "session-1")
        var state = SessionNavigationState()
        state.select(session)

        state.remove(sessionID: "session-1")

        XCTAssertNil(state.destination)
        XCTAssertNil(state.lastSelectedSessionID)
    }

    func testRemovingRememberedSessionPreservesDifferentVisibleDestination() {
        var state = SessionNavigationState(lastSelectedSessionID: "session-1")
        state.select(SessionListUtilityDestination.tasks)

        state.remove(sessionID: "session-1")

        XCTAssertEqual(state.destination, .utility(.tasks))
        XCTAssertNil(state.lastSelectedSessionID)
    }

    func testUtilityDestinationRemainsSelectedAcrossLayoutReevaluation() {
        var state = SessionNavigationState()
        state.select(SessionListUtilityDestination.settings(nil))

        let reevaluatedState = state

        XCTAssertEqual(reevaluatedState.destination, .utility(.settings(nil)))
        XCTAssertNil(reevaluatedState.selectedSessionID)
    }

    func testKanbanIsSelectableAsAUtilityDestination() {
        var state = SessionNavigationState()

        state.select(SessionListUtilityDestination.kanban)

        XCTAssertEqual(state.destination, .utility(.kanban))
        XCTAssertNil(state.selectedSessionID)
    }

    func testReselectingRootDestinationAdvancesNavigationRevision() {
        var state = SessionNavigationState()
        state.select(SessionListUtilityDestination.skills)
        let firstRevision = state.rootRevision

        state.select(SessionListUtilityDestination.skills)

        XCTAssertEqual(state.destination, .utility(.skills))
        XCTAssertGreaterThan(state.rootRevision, firstRevision)
    }

    func testReadableContentWidthsKeepSecondaryAndWorkspaceSurfacesDistinct() {
        XCTAssertEqual(AdaptiveReadableContentWidth.secondaryDestination, 800)
        XCTAssertEqual(AdaptiveReadableContentWidth.workspace, 1_000)
        XCTAssertLessThan(
            AdaptiveReadableContentWidth.secondaryDestination,
            AdaptiveReadableContentWidth.workspace
        )
    }

    func testPersistenceUsesIndependentKeysPerServer() throws {
        let suiteName = "SessionNavigationStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstServer = try XCTUnwrap(URL(string: "https://first.example.com"))
        let secondServer = try XCTUnwrap(URL(string: "https://second.example.com"))

        SessionNavigationPersistence.save("first-session", for: firstServer, defaults: defaults)
        SessionNavigationPersistence.save("second-session", for: secondServer, defaults: defaults)

        XCTAssertEqual(
            SessionNavigationPersistence.load(for: firstServer, defaults: defaults),
            "first-session"
        )
        XCTAssertEqual(
            SessionNavigationPersistence.load(for: secondServer, defaults: defaults),
            "second-session"
        )
    }
}

private enum NewChatReturnEvent: Equatable {
    case suppressedPlaceholders
    case refreshedSessions(force: Bool)
}

private actor SessionInitialLoadEventRecorder {
    enum Event: Equatable {
        case deepLinkStarted
        case refreshStarted
        case deepLinkFinished
    }

    private var events: [Event] = []

    func record(_ event: Event) {
        events.append(event)
    }

    func snapshot() -> [Event] {
        events
    }
}
