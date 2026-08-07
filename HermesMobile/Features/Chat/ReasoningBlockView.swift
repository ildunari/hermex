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
        ChatTranscriptDisplaySettings.isCardExpanded(
            userToggled: userToggledExpansion,
            startsExpanded: startsExpanded
        )
    }

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
                    accessory: AnyView(chevron)
                ) {
                    withAnimation(ChatMotion.disclosure(reduceMotion: reduceMotion)) {
                        userToggledExpansion = !isExpanded
                    }
                }
                .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand details.")

                if isExpanded {
                    // Blockquote treatment: a soft rail plus a faint wash,
                    // reading as quoted thought rather than a boxed card.
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(palette.textTertiary)
                            .frame(width: 3)

                        Text(trimmedText)
                            .font(AppFont.caption())
                            .foregroundStyle(palette.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(palette.quoteWash)
                            )
                    }
                    .padding(.leading, 4)
                    .transition(ChatMotion.disclosureTransition(reduceMotion: reduceMotion))
                }
            }
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
