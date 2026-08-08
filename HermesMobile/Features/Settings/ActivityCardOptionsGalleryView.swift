#if DEBUG
import SwiftUI

/// The four candidate treatments for a turn's expanded activity, rendered from
/// the same fixture so they can be compared directly
/// (`--surface-gallery-page 15`, one option per `--surface-gallery-option`).
///
/// The fixture deliberately contains a thought with real markdown in it —
/// bold run-headers, a list, inline code — because that is what models
/// actually emit and it is the thing option B and beyond are meant to fix.
struct ActivityCardOptionsGalleryView: View {
    /// 0 = original, 1 = markdown only, 2 = merged container, 3 = unified sections.
    var option: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                content
                    .padding(.top, 4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var title: String {
        switch option {
        case 1: "B — MARKDOWN IN THOUGHT"
        case 2: "C — ONE CONTAINER"
        case 3: "D — UNIFIED SECTIONS"
        default: "A — ORIGINAL (SHIPPING)"
        }
    }

    private var subtitle: String {
        switch option {
        case 1:
            "Same two cards. Thought renders markdown at reasoning scale, so bold run-headers and lists stop showing as literal asterisks."
        case 2:
            "Markdown, plus both blocks share one bordered container. Turn order preserved; each section still folds on its own."
        case 3:
            "One container with a rail running through it. Sections are rows on the rail rather than cards, so the turn reads as a single sequence."
        default:
            "Two separate bordered cards. Thought is plain text — the ** markers are literal."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch option {
        case 1:
            VStack(alignment: .leading, spacing: 8) {
                ReasoningBlockView(text: Self.thought, completedDuration: 12, rendersMarkdown: true)
                ToolActivityGroupView(group: Self.group)
            }
        case 2:
            MergedActivityCard(style: .stacked)
        case 3:
            MergedActivityCard(style: .railed)
        default:
            VStack(alignment: .leading, spacing: 8) {
                ReasoningBlockView(text: Self.thought, completedDuration: 12, rendersMarkdown: false)
                ToolActivityGroupView(group: Self.group)
            }
        }
    }

    // MARK: - Fixture

    /// Real reasoning shape: bold run-headers, a list, inline code. This is the
    /// text that renders as literal `**` markers today.
    static let thought = """
        **Checking the palette tokens**

        The transcript row structure decides where the rails belong, so the \
        token audit has to come first.

        - `ChatPalette.surface` is already warm in both schemes
        - `tableRule` is the only hairline used by activity blocks
        - the beam reads from `HeaderLogoColor`, not the palette

        **Deciding the container**

        One bordered container per turn, with the sections inside it, keeps \
        the turn readable without nesting disclosure inside disclosure.
        """

    static let group: ToolCallGroup = {
        let names = ["skill_view", "skill_view", "read_file", "execute_code", "search_files"]
        let calls = names.enumerated().map { index, name in
            ToolCall(
                id: "opt-\(index)",
                name: name,
                preview: nil,
                args: nil,
                duration: Double(index % 3) + 1.2,
                isError: false,
                isCompleted: true,
                batchIndex: index < 2 ? 0 : index
            )
        }
        return ToolCallGroup.live(anchorMessageID: "opt-anchor", toolCalls: calls)
    }()
}

/// Options C and D: both blocks inside one container.
private struct MergedActivityCard: View {
    enum Style {
        /// Sections stacked with a divider between them.
        case stacked
        /// Sections hung off a continuous vertical rail.
        case railed
    }

    let style: Style

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChatBackgroundStyle.storageKey) private var backgroundStyleRawValue = ChatBackgroundStyle.defaultValue.rawValue
    @AppStorage(ChatPaletteTemperature.storageKey) private var paletteTemperatureRawValue = ChatPaletteTemperature.defaultValue.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if style == .railed {
                railedBody
            } else {
                stackedBody
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(ActivityBlockChrome.shape().fill(palette.surface.opacity(0.55)))
        .overlay(ActivityBlockChrome.shape().strokeBorder(palette.tableRule, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReasoningBlockView(
                text: ActivityCardOptionsGalleryView.thought,
                completedDuration: 12,
                rendersMarkdown: true,
                drawsOwnChrome: false
            )

            Rectangle()
                .fill(palette.tableRule)
                .frame(height: 1)
                .padding(.vertical, 2)

            ToolActivityGroupView(
                group: ActivityCardOptionsGalleryView.group,
                drawsOwnChrome: false
            )
        }
    }

    /// A single rail runs the height of the card and every section hangs off
    /// it, so the turn reads as one sequence rather than a stack of parts.
    private var railedBody: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(palette.tableRule)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 10) {
                ReasoningBlockView(
                    text: ActivityCardOptionsGalleryView.thought,
                    completedDuration: 12,
                    rendersMarkdown: true,
                    drawsOwnChrome: false
                )

                ToolActivityGroupView(
                    group: ActivityCardOptionsGalleryView.group,
                    drawsOwnChrome: false
                )
            }
        }
    }

    private var palette: ChatPalette {
        ChatPalette(
            colorScheme: colorScheme,
            backgroundStyle: ChatBackgroundStyle.storedValue(backgroundStyleRawValue),
            temperature: ChatPaletteTemperature.storedValue(paletteTemperatureRawValue)
        )
    }
}
#endif
