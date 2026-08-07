import SwiftUI

/// The collapsed one-line stand-in for a turn's thinking and tool blocks.
///
/// Deliberately a `Capsule()`: at ~40pt tall any radius at or above ~20 renders
/// as a pill anyway, so this keeps the shape the transcript already uses while
/// the taller multi-row blocks carry the smaller explicit radius.
///
/// Live turns pass durations and per-tool result dots. Reconstructed history
/// passes neither, because the server persists only name, snippet, tool id,
/// message index, and args — no durations, no error state, no batch grouping.
/// That quieter form is intentional, not a bug.
struct TurnActivitySummaryRow: View {
    let reasoningDuration: TimeInterval?
    let toolCalls: [ToolCall]
    /// Whether the turn had a thinking step at all. A duration implies one, but
    /// history keeps the step while losing the duration.
    var hasReasoning: Bool = true
    var isExpanded: Bool = false
    var onTap: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChatBackgroundStyle.storageKey) private var backgroundStyleRawValue = ChatBackgroundStyle.defaultValue.rawValue
    @AppStorage(ChatPaletteTemperature.storageKey) private var paletteTemperatureRawValue = ChatPaletteTemperature.defaultValue.rawValue

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                Image(systemName: hasFailure ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasFailure ? Color.red : palette.textSecondary)

                Text(summaryText)
                    .font(AppFont.footnote())
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)

                if !resultDots.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(Array(resultDots.enumerated()), id: \.offset) { _, isError in
                            Circle()
                                .fill(isError ? Color.red : Color.green)
                                .frame(width: 5, height: 5)
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Capsule().fill(palette.surface.opacity(0.8)))
            .overlay(Capsule().strokeBorder(palette.tableRule, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summaryText)
        .accessibilityHint(isExpanded ? "Double tap to collapse activity." : "Double tap to expand activity.")
    }

    private var hasFailure: Bool {
        toolCalls.contains { $0.isError == true }
    }

    /// At most eight dots; beyond that the row becomes noise rather than a
    /// glance-able result strip.
    private var resultDots: [Bool] {
        guard toolCalls.contains(where: { $0.isCompleted }) else { return [] }
        return toolCalls.prefix(8).map { $0.isError == true }
    }

    private var summaryText: String {
        var parts: [String] = []

        if let reasoningDuration {
            parts.append(String(localized: "Thought for \(ActivityDurationFormat.string(reasoningDuration))"))
        } else if hasReasoning {
            parts.append(String(localized: "Thought"))
        }

        if !toolCalls.isEmpty {
            let count = toolCalls.count
            let base = count == 1
                ? String(localized: "ran 1 tool")
                : String(localized: "ran \(count) tools")
            let durations = toolCalls.compactMap(\.duration)
            if durations.isEmpty {
                parts.append(base)
            } else {
                parts.append(String(localized: "\(base) in \(ActivityDurationFormat.string(durations.reduce(0, +)))"))
            }
        }

        guard !parts.isEmpty else { return String(localized: "Activity") }
        return parts.joined(separator: " · ")
    }

    private var palette: ChatPalette {
        ChatPalette(
            colorScheme: colorScheme,
            backgroundStyle: ChatBackgroundStyle.storedValue(backgroundStyleRawValue),
            temperature: ChatPaletteTemperature.storedValue(paletteTemperatureRawValue)
        )
    }
}
