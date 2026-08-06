import SwiftUI

struct ReasoningBlockView: View {
    let text: String
    var isStreaming: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    completedLabel: String(localized: "Thought"),
                    accessory: AnyView(chevron)
                ) {
                    withAnimation(ChatMotion.disclosure(reduceMotion: reduceMotion)) {
                        userToggledExpansion = !isExpanded
                    }
                }
                .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand details.")

                if isExpanded {
                    Text(trimmedText)
                        .font(AppFont.caption())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .chatTimelineAccessorySurface(
                            fallbackMaterial: .thinMaterial,
                            cornerRadius: 10
                        )
                        .transition(ChatMotion.disclosureTransition(reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
