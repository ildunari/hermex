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
    /// Page 14 shows both states; page 16 is the re-parse probe.
    var page: Int = 14

    var body: some View {
        if page == 16 {
            FoldReparseProbeView()
        } else {
            states
        }
    }

    private var states: some View {
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
            // Mirrors the production composition in `ChatTranscriptView`: one
            // container, sections inside it, divider between them.
            ActivityContainerView {
                ReasoningBlockView(
                    text: Self.thought,
                    isStreaming: false,
                    completedDuration: 12,
                    drawsOwnChrome: false
                )

                ActivitySectionDivider()

                ToolActivityGroupView(group: Self.group, drawsOwnChrome: false)
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

    /// Contains real markdown on purpose: models emit `**run headers**`,
    /// lists, and inline code inside reasoning, and this specimen is the check
    /// that they render rather than showing as literal punctuation.
    static let thought = """
        **Checking the palette tokens**

        The transcript row structure decides where the rails belong, so the \
        token audit has to come first.

        - `ChatPalette.surface` is already warm in both schemes
        - `tableRule` is the only hairline used by activity blocks
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

/// Reproduces the production sibling arrangement — an activity fold and a long
/// markdown answer in the same `VStack` — and toggles the fold on a timer.
///
/// Kept as the only debug surface where the fold and a long markdown answer
/// are siblings, which is the arrangement that produced the stutter — a
/// gallery page rendering a card alone cannot show it. Note it does *not*
/// fully reproduce production: this passes a constant string, so SwiftUI can
/// skip the renderer regardless of the guard. Judge the real fix on device.
private struct FoldReparseProbeView: View {
    @State private var isCollapsed = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("FOLD RE-PARSE PROBE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                TurnActivityFoldView(
                    isCollapsed: isCollapsed,
                    initiallyCollapsed: true,
                    animatesFold: true
                ) {
                    ActivityContainerView {
                        ReasoningBlockView(
                            text: ActivityFoldSpecimen.thought,
                            completedDuration: 12,
                            drawsOwnChrome: false,
                            startsExpandedOverride: true
                        )
                        ActivitySectionDivider()
                        ToolActivityGroupView(
                            group: ActivityFoldSpecimen.group,
                            drawsOwnChrome: false,
                            startsExpandedOverride: true
                        )
                    }
                } summary: { isExpanded, toggle in
                    TurnActivitySummaryRow(
                        reasoningDuration: 12,
                        toolCalls: ActivityFoldSpecimen.group.toolCalls,
                        isExpanded: isExpanded,
                        onTap: toggle
                    )
                }

                // The sibling that must NOT re-parse.
                MarkdownRenderer(content: Self.longAnswer, typographyRole: .assistantResponse)
            }
            .padding(16)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(ChatMotion.cardExpand(reduceMotion: false)) {
                    isCollapsed.toggle()
                }
            }
        }
    }

    /// Deliberately long and structurally varied — a short string would parse
    /// fast enough to hide the cost even when it is being redone.
    static let longAnswer: String = {
        let block = """
        ## Section heading

        Running prose with **bold**, *italic*, and `inline code` so the parser \
        has real inline structure to walk rather than a flat string.

        - First bullet with `a.code.reference` inside it
        - Second bullet that wraps onto more than one line so layout has work
          - A nested child item
        1. An ordered item
        2. Another ordered item

        > A blockquote, because quote handling is a separate parse path.

        ```swift
        let palette = ChatPalette(colorScheme: .dark, backgroundStyle: .warm)
        ```
        """
        return Array(repeating: block, count: 8).joined(separator: "\n\n")
    }()
}
#endif
