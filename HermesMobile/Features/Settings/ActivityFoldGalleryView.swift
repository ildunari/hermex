#if DEBUG
import SwiftUI

/// Side-by-side of the turn-activity fold's two states
/// (`--surface-gallery-page 14`).
///
/// The point of this page is the *relationship* between collapsed and
/// expanded, not either state on its own — the complaint was that tapping
/// destroys one object and produces two unrelated ones somewhere else. Both
/// states render in one screenshot so the edges, widths, and control position
/// can be compared directly.
struct ActivityFoldGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                specimen(
                    "COLLAPSED",
                    "Resting state after the answer starts.",
                    expanded: false
                )

                specimen(
                    "EXPANDED",
                    "After tapping the row.",
                    expanded: true
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func specimen(_ title: String, _ note: String, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(note)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            ActivityFoldSpecimen(startsExpanded: expanded)
        }
    }
}

/// One fold instance, forced into a fixed state.
///
/// `TurnActivityFoldView` owns its expansion internally, so the specimen drives
/// it the same way a reader would — by tapping — rather than by reaching into
/// its state. `isCollapsed: true` puts it in the folded resting state; the
/// expanded specimen then toggles once on appear.
private struct ActivityFoldSpecimen: View {
    let startsExpanded: Bool
    @State private var toggleTrigger = false

    var body: some View {
        TurnActivityFoldView(
            isCollapsed: true,
            initiallyCollapsed: true,
            animatesFold: false
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ReasoningBlockView(
                    text: Self.thought,
                    isStreaming: false,
                    completedDuration: 12
                )
                ToolActivityGroupView(group: Self.group)
            }
        } summary: { isExpanded, toggle in
            TurnActivitySummaryRow(
                reasoningDuration: 12,
                toolCalls: Self.group.toolCalls,
                isExpanded: isExpanded,
                onTap: toggle
            )
            .task(id: startsExpanded) {
                guard startsExpanded, !isExpanded, !toggleTrigger else { return }
                toggleTrigger = true
                toggle()
            }
        }
    }

    static let thought = """
        Checked the palette tokens and the transcript row structure before \
        deciding where the rails belong.
        """

    static let group: ToolCallGroup = {
        let names = ["skill_view", "skill_view", "read_file", "execute_code", "search_files", "web_search"]
        let calls = names.enumerated().map { index, name in
            ToolCall(
                id: "fold-\(index)",
                name: name,
                preview: nil,
                args: nil,
                duration: Double(index % 3) + 1.2,
                isError: false,
                isCompleted: true,
                batchIndex: index < 2 ? 0 : index
            )
        }
        return ToolCallGroup.live(anchorMessageID: "fold-anchor", toolCalls: calls)
    }()
}
#endif
