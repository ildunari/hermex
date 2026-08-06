import SwiftUI

struct ToolCallCardView: View {
    let toolCall: ToolCall
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(ChatTranscriptDisplaySettings.toolCardsStartExpandedKey) private var startsExpanded = false
    @State private var userToggledExpansion: Bool?

    private var isExpanded: Bool {
        ChatTranscriptDisplaySettings.isCardExpanded(
            userToggled: userToggledExpansion,
            startsExpanded: startsExpanded
        )
    }

    var body: some View {
        let statusDisplay = ToolCallStatusDisplay(toolCall: toolCall)

        VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
            ActivityCapsuleView(
                orbState: ThinkingOrbState.forTool(name: toolCall.name),
                label: capsuleLabel,
                isActive: isRunning,
                completedIcon: statusIcon,
                completedIconColor: toolCall.isError == true ? .red : nil,
                completedLabel: capsuleLabel,
                accessory: AnyView(chevron)
            ) {
                withAnimation(ChatMotion.disclosure(reduceMotion: reduceMotion)) {
                    userToggledExpansion = !isExpanded
                }
            }
            .accessibilityLabel(String(localized: "\(toolCall.displayName), \(statusDisplay.detailText)"))
            .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand details.")

            if isExpanded {
                expandedContent(statusDisplay: statusDisplay)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .chatTimelineAccessorySurface(
                        fallbackMaterial: .thinMaterial,
                        cornerRadius: 12
                    )
                    // Tool-call bodies are commands, JSON, file paths, and
                    // results — code-like content that must stay left-to-right
                    // inside an RTL message (#259).
                    .forcedLeftToRight()
                    .transition(ChatMotion.disclosureTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// Short activity title in "Reading ChatPalette.swift" style: the tool's
    /// display name plus the most path-like argument, middle-truncated by the
    /// capsule's label line.
    private var capsuleLabel: String {
        let rows = ToolCallDisplayFormatter.argumentRows(from: toolCall.args)
        let pathKeys = ["path", "file_path", "filepath", "file", "cmd", "command", "query", "url"]
        let subject = pathKeys
            .compactMap { key in rows.first { $0.key.lowercased() == key }?.value }
            .first

        guard let subject, !subject.isEmpty else {
            return toolCall.displayName
        }

        // Prefer the last path component for file-ish values.
        let trimmed = subject.contains("/") && !subject.contains(" ")
            ? String(subject.split(separator: "/").last ?? Substring(subject))
            : subject
        return "\(toolCall.displayName) \(trimmed)"
    }

    private func expandedContent(statusDisplay: ToolCallStatusDisplay) -> some View {
        let displayContent = ToolCallDisplayFormatter.content(for: toolCall)

        return VStack(alignment: .leading, spacing: 7) {
            if !displayContent.argumentRows.isEmpty {
                argumentsSection(displayContent.argumentRows)
            }

            if let result = displayContent.result {
                resultSection(result)
            }

            if shouldShowStatusDetail(displayContent: displayContent) {
                statusDetail(statusDisplay.detailText)
            }
        }
    }

    private var usesStackedHeader: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var statusIcon: String {
        if toolCall.isError == true {
            return "exclamationmark.triangle.fill"
        }

        return toolCall.isCompleted ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill"
    }

    private var isRunning: Bool {
        toolCall.isError != true && !toolCall.isCompleted
    }

    private var statusColor: Color {
        if toolCall.isError == true {
            return .red
        }

        return .secondary
    }

    private func shouldShowStatusDetail(displayContent: ToolCallDisplayContent) -> Bool {
        let hasPrimaryContent = !displayContent.argumentRows.isEmpty || displayContent.result != nil
        return !hasPrimaryContent || !toolCall.isCompleted || toolCall.isError == true || toolCall.duration != nil
    }

    private func statusDetail(_ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Status")
                .font(AppFont.caption2(weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(AppFont.caption())
                .foregroundStyle(statusColor)
                .textSelection(.enabled)
        }
    }

    private func argumentsSection(_ rows: [ToolCallArgumentDisplay]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Arguments")
                .font(AppFont.caption2(weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    argumentRow(row)
                }
            }
            .padding(7)
            .chatTimelineAccessoryInsetSurface()
        }
    }

    private func resultSection(_ result: ToolCallResultDisplay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.title)
                .font(AppFont.caption2(weight: .semibold))
                .foregroundStyle(.secondary)

            Text(result.text)
                .font(result.isMonospaced ? AppFont.mono(style: .caption) : AppFont.caption())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .chatTimelineAccessoryInsetSurface()
        }
    }

    @ViewBuilder
    private func argumentRow(_ row: ToolCallArgumentDisplay) -> some View {
        if usesStackedHeader {
            VStack(alignment: .leading, spacing: 2) {
                argumentKey(row.key)
                argumentValue(row.value)
            }
        } else {
            HStack(alignment: .top, spacing: 7) {
                argumentKey(row.key)
                    .frame(width: 78, alignment: .leading)

                argumentValue(row.value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func argumentKey(_ value: String) -> some View {
        Text(value)
            .font(AppFont.mono(style: .caption2, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func argumentValue(_ value: String) -> some View {
        Text(value)
            .font(AppFont.mono(style: .caption))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

struct ToolCallStatusDisplay: Equatable {
    let collapsedText: String?
    let detailText: String

    init(toolCall: ToolCall) {
        if toolCall.isError == true {
            collapsedText = String(localized: "Failed")
            detailText = String(localized: "Failed")
            return
        }

        if toolCall.isCompleted {
            collapsedText = nil
            if let duration = toolCall.duration {
                detailText = "Completed in \(duration.formatted(.number.precision(.fractionLength(1))))s"
            } else {
                detailText = String(localized: "Completed")
            }
            return
        }

        collapsedText = String(localized: "Running")
        detailText = String(localized: "Running")
    }
}

struct TranscriptStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppFont.caption2(weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
