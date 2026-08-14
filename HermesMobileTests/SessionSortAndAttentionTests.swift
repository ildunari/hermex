import XCTest
@testable import HermesMobile

@MainActor
final class SessionSortAndAttentionTests: XCTestCase {
    // MARK: - Attention decoding

    func testAttentionDecodesApprovalPayload() throws {
        let json = """
        {
          "session_id": "s1",
          "title": "Waiting",
          "attention": { "kind": "approval", "count": 2, "severity": "critical" }
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(SessionSummary.self, from: json)
        XCTAssertEqual(session.attention?.kind, .approval)
        XCTAssertEqual(session.attention?.count, 2)
        XCTAssertEqual(session.attention?.severity, .critical)
        XCTAssertTrue(session.needsAttention)
        XCTAssertEqual(session.attentionCount, 2)
        XCTAssertTrue(session.attention?.isBlocking == true)
    }

    func testAttentionDecodesClarifyPayload() throws {
        let json = """
        {
          "session_id": "s2",
          "title": "Question",
          "attention": { "kind": "clarify", "count": 1, "severity": "question" }
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(SessionSummary.self, from: json)
        XCTAssertEqual(session.attention?.kind, .clarify)
        XCTAssertTrue(session.needsAttention)
        XCTAssertEqual(session.attentionCount, 1)
        XCTAssertFalse(session.attention?.isBlocking == true)
    }

    func testAttentionUnknownKindDoesNotFailTheRow() throws {
        let json = """
        {
          "session_id": "s3",
          "title": "Future",
          "attention": { "kind": "review", "count": 4, "severity": "info" }
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(SessionSummary.self, from: json)
        XCTAssertEqual(session.attention?.kind, .unknown)
        XCTAssertEqual(session.attention?.severity, .unknown)
        XCTAssertEqual(session.attentionCount, 4)
        XCTAssertTrue(session.needsAttention)
        XCTAssertFalse(session.attention?.isBlocking == true)
    }

    func testMissingAttentionIsIdle() throws {
        let json = """
        { "session_id": "s4", "title": "Idle" }
        """.data(using: .utf8)!

        let session = try decoder.decode(SessionSummary.self, from: json)
        XCTAssertNil(session.attention)
        XCTAssertFalse(session.needsAttention)
        XCTAssertEqual(session.attentionCount, 0)
    }

    func testZeroCountAttentionIsNotActionable() throws {
        let json = """
        {
          "session_id": "s5",
          "attention": { "kind": "approval", "count": 0, "severity": "critical" }
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(SessionSummary.self, from: json)
        XCTAssertFalse(session.needsAttention)
        XCTAssertEqual(session.attentionCount, 0)
    }

    func testReplacingTitlePreservesAttention() {
        let original = SessionSummary(
            sessionId: "s6",
            title: "Old",
            attention: SessionAttention(kind: .approval, count: 3, severity: .critical)
        )
        let renamed = original.replacingTitle(with: "New")
        XCTAssertEqual(renamed.title, "New")
        XCTAssertEqual(renamed.attention?.count, 3)
        XCTAssertEqual(renamed.attention?.kind, .approval)
    }

    // MARK: - Filters

    func testNeedsInputFilterIncludesAttentionAndPending() {
        let rows = [
            session("attn", attention: SessionAttention(kind: .clarify, count: 1, severity: .question)),
            session("pending", hasPendingUserMessage: true),
            session("idle")
        ]
        var prefs = SessionSortPreferences.default
        prefs.activeFilters = [.needsInput]
        let filtered = SessionListViewModel.applyStatusFilters(rows, preferences: prefs)
        XCTAssertEqual(filtered.map(\.sessionId), ["attn", "pending"])
    }

    func testWorkingFilterIncludesStreamingOnly() {
        let rows = [
            session("stream", isStreaming: true),
            session("attn", attention: SessionAttention(kind: .approval, count: 1, severity: .critical)),
            session("idle")
        ]
        var prefs = SessionSortPreferences.default
        prefs.activeFilters = [.working]
        let filtered = SessionListViewModel.applyStatusFilters(rows, preferences: prefs)
        XCTAssertEqual(filtered.map(\.sessionId), ["stream"])
    }

    func testUnreadFilterUsesLocalLastSeenSet() {
        let rows = [session("seen"), session("unseen")]
        var prefs = SessionSortPreferences.default
        prefs.activeFilters = [.unread]
        let filtered = SessionListViewModel.applyStatusFilters(
            rows,
            preferences: prefs,
            unreadSessionIDs: ["unseen"]
        )
        XCTAssertEqual(filtered.map(\.sessionId), ["unseen"])
    }

    func testStatusFiltersAreAdditive() {
        let rows = [
            session("stream", isStreaming: true),
            session("attn", attention: SessionAttention(kind: .clarify, count: 1, severity: .question)),
            session("idle")
        ]
        var prefs = SessionSortPreferences.default
        prefs.activeFilters = [.needsInput, .working]
        let filtered = SessionListViewModel.applyStatusFilters(rows, preferences: prefs)
        XCTAssertEqual(Set(filtered.compactMap(\.sessionId)), ["stream", "attn"])
    }

    func testArchivedRowsStayHiddenUntilToggled() {
        let rows = [session("live"), session("old", archived: true)]
        XCTAssertEqual(
            SessionListViewModel.applyStatusFilters(rows, preferences: .default).map(\.sessionId),
            ["live"]
        )
        var prefs = SessionSortPreferences.default
        prefs.includesArchived = true
        XCTAssertEqual(
            SessionListViewModel.applyStatusFilters(rows, preferences: prefs).map(\.sessionId),
            ["live", "old"]
        )
    }

    // MARK: - Ordering

    func testRecentOrderingPutsNewestFirstAndPinnedOnTop() {
        let rows = [
            session("old", lastMessageAt: 10),
            session("new", lastMessageAt: 90),
            session("pin", lastMessageAt: 5, pinned: true)
        ]
        let ordered = SessionListViewModel.applyOrdering(rows, ordering: .recent)
        XCTAssertEqual(ordered.map(\.sessionId), ["pin", "new", "old"])
    }

    func testCreatedOrderingUsesCreatedAt() {
        let rows = [
            session("later", createdAt: 20, lastMessageAt: 100),
            session("earlier", createdAt: 80, lastMessageAt: 10)
        ]
        let ordered = SessionListViewModel.applyOrdering(rows, ordering: .created)
        XCTAssertEqual(ordered.map(\.sessionId), ["earlier", "later"])
    }

    func testStatusOrderingRanksNeedsInputThenWorking() {
        let rows = [
            session("idle"),
            session("stream", isStreaming: true),
            session("attn", attention: SessionAttention(kind: .approval, count: 1, severity: .critical))
        ]
        let ordered = SessionListViewModel.applyOrdering(rows, ordering: .status)
        XCTAssertEqual(ordered.map(\.sessionId), ["attn", "stream", "idle"])
    }

    func testTokensOrderingSumsInputAndOutput() {
        let rows = [
            session("small", inputTokens: 10, outputTokens: 10),
            session("large", inputTokens: 80, outputTokens: 20)
        ]
        let ordered = SessionListViewModel.applyOrdering(rows, ordering: .tokens)
        XCTAssertEqual(ordered.map(\.sessionId), ["large", "small"])
    }

    func testCostOrderingUsesEstimatedCost() {
        let rows = [
            session("cheap", estimatedCost: 0.2),
            session("pricey", estimatedCost: 4.5)
        ]
        let ordered = SessionListViewModel.applyOrdering(rows, ordering: .cost)
        XCTAssertEqual(ordered.map(\.sessionId), ["pricey", "cheap"])
    }

    // MARK: - Grouping

    func testDateGroupingSplitsPinnedTodayYesterdayEarlier() {
        let calendar = Calendar.current
        let now = Date()
        let today = now.timeIntervalSince1970
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!.timeIntervalSince1970
        let earlier = calendar.date(byAdding: .day, value: -8, to: now)!.timeIntervalSince1970

        let rows = [
            session("pin", lastMessageAt: earlier, pinned: true),
            session("today", lastMessageAt: today),
            session("yday", lastMessageAt: yesterday),
            session("old", lastMessageAt: earlier)
        ]
        let sections = SessionListViewModel.groupedSections(
            rows,
            preferences: .default,
            calendar: calendar
        )
        XCTAssertEqual(sections.map(\.id), ["pinned", "today", "yesterday", "earlier"])
        XCTAssertEqual(sections[0].sessions.map(\.sessionId), ["pin"])
        XCTAssertEqual(sections[1].sessions.map(\.sessionId), ["today"])
        XCTAssertEqual(sections[2].sessions.map(\.sessionId), ["yday"])
        XCTAssertEqual(sections[3].sessions.map(\.sessionId), ["old"])
    }

    func testStatusGroupingPutsNeedsInputBeforeWorkingBeforeIdle() {
        var prefs = SessionSortPreferences.default
        prefs.grouping = .status
        let rows = [
            session("idle"),
            session("stream", isStreaming: true),
            session("attn", attention: SessionAttention(kind: .clarify, count: 1, severity: .question))
        ]
        let sections = SessionListViewModel.groupedSections(rows, preferences: prefs)
        XCTAssertEqual(sections.map(\.id), ["needs-input", "working", "idle"])
        XCTAssertEqual(sections[0].sessions.map(\.sessionId), ["attn"])
        XCTAssertEqual(sections[1].sessions.map(\.sessionId), ["stream"])
        XCTAssertEqual(sections[2].sessions.map(\.sessionId), ["idle"])
    }

    func testProjectGroupingUsesCatalogDisplayNameNotRawId() {
        var prefs = SessionSortPreferences.default
        prefs.grouping = .project
        let rows = [
            session("cell", projectId: "7a6b0ff1f141"),
            session("cron", projectId: "bf45c9f4c675"),
            session("none")
        ]
        let catalog = [
            ProjectSummary(projectId: "7a6b0ff1f141", name: "Cell Work"),
            ProjectSummary(projectId: "bf45c9f4c675", name: "Cron Jobs")
        ]
        let sections = SessionListViewModel.groupedSections(
            rows,
            preferences: prefs,
            projects: catalog
        )
        XCTAssertEqual(sections.map(\.id), ["7a6b0ff1f141", "bf45c9f4c675", "No Project"])
        XCTAssertEqual(sections.map(\.title), ["Cell Work", "Cron Jobs", "No Project"])
    }

    func testProjectGroupingFallsBackToUntitledWhenCatalogMisses() {
        var prefs = SessionSortPreferences.default
        prefs.grouping = .project
        let rows = [session("orphan", projectId: "deadbeef")]
        let sections = SessionListViewModel.groupedSections(rows, preferences: prefs)
        XCTAssertEqual(sections.map(\.id), ["deadbeef"])
        XCTAssertEqual(sections.map(\.title), ["Untitled Project"])
    }

    func testProjectGroupingSortsByDisplayNameAndPutsMissingLast() {
        var prefs = SessionSortPreferences.default
        prefs.grouping = .project
        let rows = [
            session("zeta", projectId: "z-id"),
            session("alpha", projectId: "a-id"),
            session("none")
        ]
        let catalog = [
            ProjectSummary(projectId: "z-id", name: "Zeta"),
            ProjectSummary(projectId: "a-id", name: "Alpha")
        ]
        let sections = SessionListViewModel.groupedSections(
            rows,
            preferences: prefs,
            projects: catalog
        )
        XCTAssertEqual(sections.map(\.id), ["a-id", "z-id", "No Project"])
        XCTAssertEqual(sections.map(\.title), ["Alpha", "Zeta", "No Project"])
    }

    func testProfileGroupingUsesProfileName() {
        var prefs = SessionSortPreferences.default
        prefs.grouping = .profile
        let rows = [
            session("work", profile: "work"),
            session("coding", profile: "coding"),
            session("none")
        ]
        let sections = SessionListViewModel.groupedSections(rows, preferences: prefs)
        XCTAssertEqual(sections.map(\.id), ["coding", "work", "No Profile"])
    }

    // MARK: - Preference persistence

    func testFilterRoundTripIsStable() {
        let filters: Set<SessionStatusFilter> = [.needsInput, .working]
        let encoded = SessionSortPreferences.encodeFilters(filters)
        XCTAssertEqual(encoded, "needsInput,working")
        XCTAssertEqual(SessionSortPreferences.decodeFilters(encoded), filters)
        XCTAssertTrue(SessionSortPreferences.decodeFilters("bogus").isEmpty)
        XCTAssertTrue(SessionSortPreferences.default.isModified == false)
        var prefs = SessionSortPreferences.default
        prefs.ordering = .tokens
        XCTAssertTrue(prefs.isModified)
        prefs = .default
        prefs.usesInboxStyle = true
        XCTAssertTrue(prefs.isModified)
        prefs = .default
        prefs.showsAllProfiles = true
        XCTAssertTrue(prefs.isModified)
    }

    // MARK: - Helpers

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func session(
        _ id: String,
        createdAt: Double? = nil,
        lastMessageAt: Double? = nil,
        pinned: Bool? = nil,
        archived: Bool? = nil,
        projectId: String? = nil,
        profile: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        estimatedCost: Double? = nil,
        isStreaming: Bool? = nil,
        hasPendingUserMessage: Bool? = nil,
        attention: SessionAttention? = nil
    ) -> SessionSummary {
        SessionSummary(
            sessionId: id,
            title: id,
            createdAt: createdAt,
            lastMessageAt: lastMessageAt,
            pinned: pinned,
            archived: archived,
            projectId: projectId,
            profile: profile,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCost: estimatedCost,
            isStreaming: isStreaming,
            hasPendingUserMessage: hasPendingUserMessage,
            attention: attention
        )
    }
}
