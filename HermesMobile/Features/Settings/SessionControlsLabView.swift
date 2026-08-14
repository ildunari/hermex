#if DEBUG
import SwiftUI

/// Deterministic host for the session-list header controls
/// (`--session-controls-lab`).
///
/// Gesture behaviour for the bell and sort menu has to be verified without a
/// server: the assertions are about filtering, grouping, and badge mechanics,
/// which must hold regardless of whose sessions are on screen. This mounts the
/// production `SessionListHeaderControls` and the production grouping/filter
/// functions over fixed rows, so a passing test exercises shipping code rather
/// than a parallel reimplementation.
struct SessionControlsLabView: View {
    @State private var preferences = SessionSortPreferences.default

    /// Fixed fixtures: one blocking approval, one clarify, one streaming, one
    /// idle, one archived. Timestamps are relative so date grouping is stable.
    private static let fixtures: [SessionSummary] = {
        let now = Date().timeIntervalSince1970
        let day: Double = 86_400
        return [
            SessionSummary(
                sessionId: "approval",
                title: "Needs approval",
                lastMessageAt: now - 60,
                projectId: "hermex",
                profile: "coding",
                inputTokens: 900,
                outputTokens: 100,
                estimatedCost: 4.2,
                attention: SessionAttention(kind: .approval, count: 2, severity: .critical)
            ),
            SessionSummary(
                sessionId: "clarify",
                title: "Asked a question",
                lastMessageAt: now - 3_600,
                projectId: "hermex",
                profile: "gpt",
                inputTokens: 200,
                outputTokens: 50,
                estimatedCost: 0.8,
                attention: SessionAttention(kind: .clarify, count: 1, severity: .question)
            ),
            SessionSummary(
                sessionId: "working",
                title: "Currently streaming",
                lastMessageAt: now - 7_200,
                projectId: "other",
                profile: "coding",
                inputTokens: 400,
                outputTokens: 400,
                estimatedCost: 2.1,
                isStreaming: true
            ),
            SessionSummary(
                sessionId: "idle",
                title: "Idle session",
                lastMessageAt: now - (3 * day),
                projectId: "other",
                profile: "gpt",
                inputTokens: 50,
                outputTokens: 25,
                estimatedCost: 0.1
            ),
            SessionSummary(
                sessionId: "archived",
                title: "Archived session",
                lastMessageAt: now - (9 * day),
                archived: true,
                projectId: "hermex",
                profile: "coding",
                inputTokens: 10,
                outputTokens: 10,
                estimatedCost: 0.05
            )
        ]
    }()

    private static let catalog: [ProjectSummary] = [
        ProjectSummary(projectId: "hermex", name: "Hermex"),
        ProjectSummary(projectId: "other", name: "Other")
    ]

    private var filtered: [SessionSummary] {
        SessionListViewModel.applyStatusFilters(Self.fixtures, preferences: preferences)
    }

    private var sections: [SessionGroupedSection] {
        SessionListViewModel.groupedSections(
            filtered,
            preferences: preferences,
            projects: Self.catalog
        )
    }

    private var attentionCount: Int {
        Self.fixtures.reduce(0) { $0 + $1.attentionCount }
    }

    private var hasBlockingAttention: Bool {
        Self.fixtures.contains { $0.attention?.isBlocking == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sessions")
                    .font(.title2.weight(.semibold))
                Spacer()
                SessionListHeaderControls(
                    attentionCount: attentionCount,
                    hasBlockingAttention: hasBlockingAttention,
                    preferences: preferences,
                    onTapBell: {
                        if preferences.activeFilters == [.needsInput] {
                            preferences.activeFilters = []
                        } else {
                            preferences.activeFilters = [.needsInput]
                        }
                    },
                    onUpdatePreferences: { preferences = $0 }
                )
            }
            .padding(.horizontal, 16)

            // Visible-row roster the test asserts against, newline separated so
            // one element read gives the exact list and order on screen.
            Text(filtered.compactMap(\.sessionId).joined(separator: ","))
                .accessibilityIdentifier("lab.visibleRows")
                .font(.caption.monospaced())
                .padding(.horizontal, 16)

            Text(sections.map(\.id).joined(separator: ","))
                .accessibilityIdentifier("lab.sectionIDs")
                .font(.caption.monospaced())
                .padding(.horizontal, 16)

            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.sessions, id: \.sessionId) { session in
                            Text(session.title ?? session.sessionId ?? "—")
                        }
                    }
                }
            }
        }
        .padding(.top, 12)
    }
}
#endif
