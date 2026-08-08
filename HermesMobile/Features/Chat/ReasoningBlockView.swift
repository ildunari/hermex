import SwiftUI

struct ReasoningBlockView: View {
    let text: String
    var isStreaming: Bool = false
    /// How long the reasoning step took, when known (wired from
    /// ChatTranscriptView). Drives the "Thought for 3.4s" completed label;
    /// nil keeps the plain "Thought".
    var completedDuration: TimeInterval? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChatBackgroundStyle.storageKey) private var backgroundStyleRawValue = ChatBackgroundStyle.defaultValue.rawValue
    @AppStorage(ChatPaletteTemperature.storageKey) private var paletteTemperatureRawValue = ChatPaletteTemperature.defaultValue.rawValue
    @AppStorage(ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey) private var startsExpanded = false
    @State private var userToggledExpansion: Bool?

    private var isExpanded: Bool {
        #if DEBUG
        // Debug motion lab drives expansion on a timer so open/close can be
        // recorded deterministically; nil in every production path.
        if let forced = disclosureLabExpansion { return forced }
        #endif
        return ChatTranscriptDisplaySettings.isCardExpanded(
            userToggled: userToggledExpansion,
            startsExpanded: startsExpanded
        )
    }

    #if DEBUG
    @Environment(\.disclosureLabExpansion) private var disclosureLabExpansion
    #endif

    var body: some View {
        if let trimmedText {
            VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
                // `isStreaming` is fed from `ChatViewModel.isReasoningPhaseActive`
                // at the live call sites (ChatTranscriptView): the orb/beam
                // animate for the entire reasoning *step* — including long
                // pauses between reasoning deltas — and settle only when the
                // turn semantically moves on (tool call, answer text, or end).
                ActivityCapsuleView(
                    orbState: .thinking,
                    label: String(localized: "Thinking…"),
                    isActive: isStreaming,
                    completedIcon: "brain",
                    completedLabel: completedLabelText,
                    accessory: AnyView(chevron),
                    onTap: {
                        withAnimation(ChatMotion.cardExpand(reduceMotion: reduceMotion)) {
                            userToggledExpansion = !isExpanded
                        }
                    },
                    // Expanded, the block itself is the bordered container, so
                    // the header must not draw a competing pill inside it.
                    chrome: isExpanded ? .none : .pill
                )
                .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand details.")

                if isExpanded {
                    // Quiet indented body: a thin rail with the thought hanging
                    // off it, matching the expanded tool block rather than
                    // nesting a washed slab inside a card.
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(palette.tableRule)
                            .frame(width: 2)

                        Text(trimmedText)
                            .font(AppFont.caption())
                            .foregroundStyle(palette.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Emerges from inside the opening card rather than
                            // arriving with it.
                            .opacity(isExpanded ? 1 : 0)
                            .animation(
                                ChatMotion.cardContent(
                                    reduceMotion: reduceMotion,
                                    delay: isExpanded ? ChatMotion.cardContentLeadIn : 0
                                ),
                                value: isExpanded
                            )
                    }
                    .padding(.leading, 4)
                    .transition(ChatMotion.cardContentTransition(reduceMotion: reduceMotion))
                }
            }
            // One container for the whole block when open — same treatment the
            // tool block uses, so thinking and tools read as one family.
            .modifier(ReasoningBlockChrome(palette: palette, isEnabled: isExpanded))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completedLabelText: String {
        guard let completedDuration else {
            return String(localized: "Thought")
        }
        return String(localized: "Thought for \(ActivityDurationFormat.string(completedDuration))")
    }

    private var palette: ChatPalette {
        ChatPalette(
            colorScheme: colorScheme,
            backgroundStyle: ChatBackgroundStyle.storedValue(backgroundStyleRawValue),
            temperature: ChatPaletteTemperature.storedValue(paletteTemperatureRawValue)
        )
    }

    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var trimmedText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Shared container geometry for expanded activity blocks (thinking + tools).
///
/// 10pt continuous matches `MarkerMessageCardView` and the timeline accessory
/// surface, so an expanded block reads as the same family of card as the rest
/// of the transcript instead of an oversized pill.
enum ActivityBlockChrome {
    static let cornerRadius: CGFloat = 10

    static func shape() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

/// One border for an expanded thinking block. Collapsed, the header capsule
/// keeps its own pill chrome and this does nothing.
private struct ReasoningBlockChrome: ViewModifier {
    let palette: ChatPalette
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(ActivityBlockChrome.shape().fill(palette.surface.opacity(0.8)))
                .overlay(ActivityBlockChrome.shape().strokeBorder(palette.tableRule, lineWidth: 1))
        } else {
            content
        }
    }
}
