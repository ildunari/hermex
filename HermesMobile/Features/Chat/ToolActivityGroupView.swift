import SwiftUI

struct ToolActivityGroupView: View {
    let group: ToolCallGroup
    /// Live-phase override fed from `ChatViewModel.isToolPhaseActive` at the
    /// live call sites (defaults false for completed/historical groups). Keeps
    /// the capsule animating through the "composing the next tool call"
    /// window: every call in the live group may already be complete while the
    /// turn is still semantically in its tool step (the backend emits no
    /// argument-streaming events, so that window is otherwise silent).
    var isPhaseActive: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ChatTranscriptDisplaySettings.toolCardsStartExpandedKey) private var startsExpanded = false
    @State private var userToggledExpansion: Bool?

    private var isExpanded: Bool {
        ChatTranscriptDisplaySettings.isCardExpanded(
            userToggled: userToggledExpansion,
            startsExpanded: startsExpanded
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
            ActivityCapsuleView(
                orbState: runningOrbState,
                label: capsuleLabel,
                isActive: isRunning,
                completedIcon: activityIcon,
                completedIconColor: group.hasFailedTool ? .red : nil,
                completedLabel: completedCapsuleLabel,
                accessory: AnyView(chevron)
            ) {
                withAnimation(ChatMotion.disclosure(reduceMotion: reduceMotion)) {
                    userToggledExpansion = !isExpanded
                }
            }
            .accessibilityLabel(activityAccessibilityLabel)
            .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand details.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(group.toolCalls) { toolCall in
                        ToolCallCardView(toolCall: toolCall, isNestedInGroup: true)
                    }
                }
                .padding(.leading, 8)
                .transition(ChatMotion.disclosureTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// Live label: verb from the active tool plus the group count, e.g.
    /// "Reading files · 3". Single-tool groups just use the verb phrase.
    private var capsuleLabel: String {
        let verb = activityVerb
        guard group.toolCalls.count > 1 else { return verb }
        return "\(verb) · \(group.toolCalls.count)"
    }

    private var completedCapsuleLabel: String {
        if group.hasFailedTool {
            return String(localized: "Tool failed")
        }
        let count = group.toolCalls.count
        let base = count == 1
            ? String(localized: "Ran 1 tool")
            : String(localized: "Ran \(count) tools")

        // Sum reported durations for a "Ran 3 tools in 8s" summary; if no
        // call reported one, keep the plain count label.
        let durations = group.toolCalls.compactMap(\.duration)
        guard !durations.isEmpty else { return base }
        let total = durations.reduce(0, +)
        return String(localized: "\(base) in \(ActivityDurationFormat.string(total))")
    }

    private var activityVerb: String {
        switch runningOrbState {
        case .thinking:
            String(localized: "Thinking")
        case .searching:
            String(localized: "Reading")
        case .writing:
            String(localized: "Writing")
        case .connecting:
            String(localized: "Connecting")
        case .working:
            String(localized: "Working")
        }
    }

    private var activityIcon: String {
        if group.hasFailedTool {
            return "exclamationmark.triangle.fill"
        }

        return group.isComplete ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill"
    }

    private var isRunning: Bool {
        !group.hasFailedTool && (!group.isComplete || isPhaseActive)
    }

    private var runningOrbState: ThinkingOrbState {
        let activeTool = group.toolCalls.first { !$0.isCompleted } ?? group.toolCalls.last
        return ThinkingOrbState.forTool(name: activeTool?.name)
    }

    private var activityAccessibilityLabel: String {
        "\(group.activityTitle), \(activityStateText), \(summaryText)"
    }

    private var activityStateText: String {
        if group.hasFailedTool {
            return String(localized: "Failed")
        }

        return group.isComplete ? String(localized: "Completed") : String(localized: "Running")
    }

    private var summaryText: String {
        let names = group.toolCalls.map(\.displayName)
        let uniqueNames = names.reduce(into: [String]()) { result, name in
            if !result.contains(name) {
                result.append(name)
            }
        }

        guard !uniqueNames.isEmpty else {
            return String(localized: "No tools")
        }

        let visibleNames = uniqueNames.prefix(3)
        let remainingCount = uniqueNames.count - visibleNames.count
        let visibleSummary = visibleNames.joined(separator: ", ")

        guard remainingCount > 0 else {
            return visibleSummary
        }

        return "\(visibleSummary), +\(remainingCount)"
    }
}
