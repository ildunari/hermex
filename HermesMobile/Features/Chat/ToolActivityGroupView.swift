import SwiftUI

struct ToolActivityGroupView: View {
    let group: ToolCallGroup
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
                        ToolCallCardView(toolCall: toolCall)
                    }
                }
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
        return count == 1
            ? String(localized: "Ran 1 tool")
            : String(localized: "Ran \(count) tools")
    }

    private var activityVerb: String {
        switch runningOrbState {
        case .searching:
            String(localized: "Reading")
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
        !group.hasFailedTool && !group.isComplete
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
