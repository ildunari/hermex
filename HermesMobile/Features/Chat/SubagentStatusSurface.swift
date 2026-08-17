import SwiftUI

struct SubagentStatusSurface: View {
    let children: [SubagentRun]
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.planDockHeight) private var availableHeight
    @AppStorage(ChatPaletteTemperature.storageKey) private var paletteTemperatureRawValue = ChatPaletteTemperature.defaultValue.rawValue
    @AppStorage(ActivityBeamStyle.storageKey) private var beamStyleRawValue = ActivityBeamStyle.defaultValue.rawValue
    @AppStorage(HeaderLogoColor.storageKey) private var headerLogoColorHex = HeaderLogoColor.defaultHex
    @State private var expandedRowID: String?

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                details
            }
            header
        }
        .fixedSize(horizontal: true, vertical: false)
        .composerStatusSurface(
            isExpanded: isExpanded,
            palette: palette,
            beamStyle: beamStyle,
            beamActive: isExpanded && hasActiveChildren && beamStyle.isVisible
        )
        .onChange(of: children.map(\.id)) { _, ids in
            if let expandedRowID, !ids.contains(expandedRowID) {
                self.expandedRowID = nil
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        Button {
            withAnimation(ChatMotion.cardExpand(reduceMotion: reduceMotion)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                aggregateStatusGlyph

                Text(aggregateLabel)
                    .font(AppFont.footnote())
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            .padding(.horizontal, isExpanded
                ? ComposerStatusSurfaceMetrics.expandedHeaderHorizontalPadding
                : ComposerStatusSurfaceMetrics.collapsedHorizontalPadding)
            .padding(.vertical, isExpanded
                ? ComposerStatusSurfaceMetrics.expandedHeaderVerticalPadding
                : ComposerStatusSurfaceMetrics.collapsedVerticalPadding)
            .frame(minHeight: isExpanded
                ? ComposerStatusSurfaceMetrics.expandedHeaderHeight
                : ComposerStatusSurfaceMetrics.collapsedHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Agents, \(aggregateLabel).")
        .accessibilityHint(isExpanded ? "Double tap to collapse the agents list." : "Double tap to expand the agents list.")
        .accessibilityIdentifier(ActivityAccessibilityID.subagentsHeader)
    }

    @ViewBuilder
    private var aggregateStatusGlyph: some View {
        if hasActiveChildren, !reduceMotion {
            ProgressView()
                .controlSize(.mini)
                .tint(.accentColor)
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
        } else {
            Image(systemName: aggregateSystemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(aggregateTint)
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
        }
    }

    private var details: some View {
        Group {
            if hasActiveChildren {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    rows(now: context.date)
                }
            } else {
                rows(now: Date())
            }
        }
        .frame(height: detailsHeight, alignment: .top)
        .accessibilityIdentifier(ActivityAccessibilityID.subagentsRowsScroll)
    }

    private func rows(now: Date) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                summaryHeader
                ForEach(children) { child in
                    SubagentStatusRow(
                        child: child,
                        now: now,
                        isExpanded: expandedRowID == child.id,
                        palette: palette,
                        onToggle: {
                            withAnimation(ChatMotion.quickState(reduceMotion: reduceMotion)) {
                                expandedRowID = expandedRowID == child.id ? nil : child.id
                            }
                        }
                    )
                    if child.id != children.last?.id {
                        Divider().overlay(palette.tableRule)
                    }
                }
            }
            .frame(width: 328, alignment: .leading)
            .padding(.horizontal, ComposerStatusSurfaceMetrics.horizontalPadding)
            .padding(.top, ComposerStatusSurfaceMetrics.topPadding)
            .padding(.bottom, ComposerStatusSurfaceMetrics.bottomPadding)
        }
        .scrollClipDisabled(false)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.automatic)
    }

    private var summaryHeader: some View {
        HStack {
            Text("Agents")
                .font(AppFont.footnote().weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(aggregateLabel)
                .font(AppFont.caption())
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.bottom, 7)
    }

    private var detailsHeight: CGFloat {
        let natural = CGFloat(children.count) * 68 + 42
        return min(max(110, natural), min(390, max(160, availableHeight * 0.48)))
    }

    private var hasActiveChildren: Bool { children.contains { $0.lifecycle.isActive } }
    private var activeCount: Int { children.count { $0.lifecycle.isActive } }
    private var failedCount: Int { children.count { $0.lifecycle.isFailure } }

    private var aggregateLabel: String {
        if activeCount > 0 {
            return activeCount == 1 ? String(localized: "1 agent running") : String(localized: "\(activeCount) agents running")
        }
        if failedCount > 0 {
            return String(localized: "\(children.count) agents · \(failedCount) failed")
        }
        if children.allSatisfy({ $0.lifecycle == .completed }) {
            return String(localized: "\(children.count) agents · done")
        }
        return String(localized: "\(children.count) agents · updating")
    }

    private var aggregateSystemImage: String {
        if failedCount > 0 { return "exclamationmark.circle.fill" }
        if children.allSatisfy({ $0.lifecycle == .completed }) { return "checkmark.circle.fill" }
        return "circle.fill"
    }

    private var aggregateTint: Color {
        if failedCount > 0 { return .red.opacity(0.8) }
        if children.allSatisfy({ $0.lifecycle == .completed }) { return .green.opacity(0.85) }
        return palette.textTertiary
    }

    private var palette: ChatPalette {
        ChatPalette(
            colorScheme: colorScheme,
            temperature: ChatPaletteTemperature.storedValue(paletteTemperatureRawValue)
        )
    }

    private var beamStyle: BeamStyle {
        let stored = ActivityBeamStyle.storedValue(beamStyleRawValue)
        let effective: ActivityBeamStyle = stored == .off ? .off : .accent
        return BeamStyle(
            resolved: effective.resolved(
                palette: palette,
                colorScheme: colorScheme,
                accent: HeaderLogoColor.color(for: headerLogoColorHex)
            )
        )
    }
}

private struct SubagentStatusRow: View {
    let child: SubagentRun
    let now: Date
    let isExpanded: Bool
    let palette: ChatPalette
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: child.lifecycle.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint)
                        .accessibilityHidden(true)
                    Text(child.displayLabel)
                        .font(AppFont.footnote().weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(isExpanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(child.lifecycle.label)
                        .font(AppFont.caption().weight(.semibold))
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }

                if let compactMetadata {
                    Text(compactMetadata)
                        .font(AppFont.caption())
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }

                if isExpanded {
                    expandedDetails
                        .accessibilityIdentifier(ActivityAccessibilityID.subagentDetails(child.id))
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isExpanded ? "Double tap to hide agent details." : "Double tap to show agent details.")
        .accessibilityIdentifier(ActivityAccessibilityID.subagentRow(child.id))
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let prompt = nonempty(child.prompt), prompt != child.displayLabel {
                detail(label: "Prompt", value: prompt)
            }
            if let tool = nonempty(child.currentTool) {
                detail(label: "Current activity", value: tool)
            }
            detail(label: "Status / duration", value: statusDuration)
            if let modelEffort { detail(label: "Model / reasoning", value: modelEffort) }
            if let count = child.toolCount { detail(label: "Tool calls", value: "\(count)") }
            if let usageLabel { detail(label: "Tokens", value: usageLabel) }
            if let error = nonempty(child.error) { detail(label: "Error", value: error) }
        }
        .padding(.leading, 22)
    }

    private func detail(label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(AppFont.caption().weight(.semibold)).foregroundStyle(palette.textTertiary)
            Text(value).font(AppFont.footnote()).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var compactMetadata: String? {
        [nonempty(child.model), nonempty(child.reasoningEffort)?.capitalized, durationLabel, child.toolCount.map { "\($0) tools" }]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private var modelEffort: String? {
        [nonempty(child.model), nonempty(child.reasoningEffort)?.capitalized]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private var durationLabel: String? {
        guard let duration = child.duration(at: now) else { return nil }
        let seconds = Int(duration.rounded(.down))
        return seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }

    private var statusDuration: String {
        [child.lifecycle.label, durationLabel].compactMap { $0 }.joined(separator: " · ")
    }

    private var usageLabel: String? {
        guard child.lifecycle.isTerminal, let usage = child.usage else { return nil }
        let parts = [
            usage.inputTokens.map { "\(tokenLabel($0)) in" },
            usage.outputTokens.map { "\(tokenLabel($0)) out" }
        ].compactMap { $0 }
        return parts.joined(separator: " · ").nilIfEmpty
    }

    private func tokenLabel(_ value: Int64) -> String {
        value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000) : "\(value)"
    }

    private var statusTint: Color {
        if child.lifecycle.isFailure { return .red.opacity(0.8) }
        if child.lifecycle == .completed { return .green.opacity(0.85) }
        if child.lifecycle.isActive { return .accentColor }
        return palette.textTertiary
    }

    private var accessibilityLabel: String {
        [child.displayLabel, child.lifecycle.label, compactMetadata, usageLabel, nonempty(child.error)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
