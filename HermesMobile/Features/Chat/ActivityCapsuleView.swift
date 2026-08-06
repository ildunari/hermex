import SwiftUI

/// Shared "how long did that take" formatting for activity capsules:
/// one decimal under 10 seconds ("3.4s"), whole seconds after ("12s").
enum ActivityDurationFormat {
    static func string(_ duration: TimeInterval) -> String {
        if duration < 10 {
            return String(format: "%.1fs", duration)
        }
        return "\(Int(duration.rounded()))s"
    }
}

/// Collapsed chip for live reasoning/tool activity: an orb, a shimmering
/// label, and an optional traveling border beam while work is in flight.
/// Self-sizing — callers should not stretch it to full width. The whole
/// capsule is a tap target for the caller's expand/collapse.
struct ActivityCapsuleView: View {
    let orbState: ThinkingOrbState
    let label: String
    let isActive: Bool
    var completedIcon: String = "checkmark.circle.fill"
    var completedIconColor: Color?
    var completedLabel: String?
    var accessory: AnyView?
    var onTap: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(ChatBackgroundStyle.storageKey) private var backgroundStyleRawValue = ChatBackgroundStyle.defaultValue.rawValue
    @AppStorage(ChatPaletteTemperature.storageKey) private var paletteTemperatureRawValue = ChatPaletteTemperature.defaultValue.rawValue
    @AppStorage(ActivityBeamStyle.storageKey) private var beamStyleRawValue = ActivityBeamStyle.defaultValue.rawValue
    @AppStorage(HeaderLogoColor.storageKey) private var headerLogoColorHex = HeaderLogoColor.defaultHex

    /// True during the two-sweep entrance right after activation; the beam
    /// then settles to reduced strength while work continues.
    @State private var entranceBoost = false

    /// Completion choreography: when work finishes, the orb first freezes
    /// (cross-dissolve to its static frame), then dissolves to the completed
    /// icon, while one final full-strength beam sweep plays and fades.
    private enum CompletionPhase {
        /// No choreography in flight — the leading glyph simply follows
        /// `isActive` (historical capsules render here directly).
        case idle
        /// Orb is frozen at a static frame, about to become the icon.
        case freezingOrb
    }

    @State private var completionPhase: CompletionPhase = .idle
    /// Drives the single farewell beam sweep after completion.
    @State private var finaleSweep = false

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        let displayLabel = isActive ? label : (completedLabel ?? label)

        Button {
            onTap?()
        } label: {
            HStack(alignment: usesAccessibilityLayout ? .top : .center, spacing: 8) {
                leadingGlyph

                labelText(displayLabel)

                if let accessory {
                    accessory
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .modifier(CapsuleChrome(
                palette: palette,
                beamStyle: beamStyle,
                beamActive: (isActive || finaleSweep) && beamStyle.isVisible,
                usesAccessibilityLayout: usesAccessibilityLayout
            ))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(displayLabel: displayLabel))
        .task(id: isActive) {
            guard isActive else {
                entranceBoost = false
                return
            }
            entranceBoost = true
            // Two full sweeps at full strength, then settle.
            let sweeps = 2 * max(0.5, resolvedBeam.cycleDuration)
            try? await Task.sleep(nanoseconds: UInt64(sweeps * 1_000_000_000))
            withAnimation(.easeOut(duration: 0.6)) {
                entranceBoost = false
            }
        }
        .onChange(of: isActive) { wasActive, nowActive in
            guard wasActive, !nowActive else {
                // Re-activation (or spurious change) cancels any finale.
                completionPhase = .idle
                finaleSweep = false
                return
            }
            guard !reduceMotion else {
                // Reduce Motion: instant swap, no choreography.
                completionPhase = .idle
                finaleSweep = false
                return
            }
            runCompletionChoreography()
        }
    }

    // MARK: - Completion choreography

    /// Total ~0.35s glyph choreography: the orb holds a frozen frame briefly,
    /// then cross-dissolves to the completed icon, while one full-strength
    /// beam sweep plays and fades out.
    private func runCompletionChoreography() {
        completionPhase = .freezingOrb
        finaleSweep = true
        let sweepDuration = max(0.5, resolvedBeam.cycleDuration)

        Task { @MainActor in
            // Hold the frozen orb frame briefly.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !isActive else { return }
            // Cross-dissolve frozen orb → completed icon (0.15 + 0.20 ≈ 0.35s).
            withAnimation(.easeInOut(duration: 0.2)) {
                completionPhase = .idle
            }
            // Let the farewell sweep finish one cycle, then fade it out
            // (the beam modifier animates its own 0.4s fade on deactivation).
            try? await Task.sleep(nanoseconds: UInt64(sweepDuration * 1_000_000_000))
            guard !isActive else { return }
            finaleSweep = false
        }
    }

    // MARK: - Leading glyph

    @ViewBuilder
    private var leadingGlyph: some View {
        ZStack {
            if isActive {
                ThinkingOrbView(state: orbState, size: 20, color: .secondary)
                    .transition(.opacity)
            } else if completionPhase == .freezingOrb {
                // Frozen frame of the same orb: the first beat of the
                // completion cross-dissolve.
                ThinkingOrbView(state: orbState, size: 20, color: .secondary, paused: true)
                    .transition(.opacity)
            } else {
                Image(systemName: completedIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(completedIconColor ?? palette.textSecondary)
                    .frame(width: 20, height: 20)
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.15),
            value: isActive
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: completionPhase == .freezingOrb
        )
    }

    // MARK: - Label

    @ViewBuilder
    private func labelText(_ value: String) -> some View {
        let styled = Text(value).font(AppFont.subheadline())
        let base = styled
            .lineLimit(usesAccessibilityLayout ? 2 : 1)
            .truncationMode(.middle)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: usesAccessibilityLayout ? .infinity : nil, alignment: .leading)
            .foregroundStyle(palette.textSecondary)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: value)

        if isActive && !reduceMotion && !usesAccessibilityLayout {
            base.overlay {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 86_400)
                    let phase = (t / 2).truncatingRemainder(dividingBy: 1)
                    shimmerHighlight(phase: phase, text: styled)
                }
            }
        } else {
            base
        }
    }

    /// Skeleton-loader sweep: a narrow bright band crossing the label left to
    /// right, masked to the glyphs so only the text lights up.
    private func shimmerHighlight(phase: Double, text: Text) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let bandWidth = max(24, width * 0.45)
            // Travel from fully off-screen left to fully off-screen right.
            let x = -bandWidth + (width + 2 * bandWidth) * phase

            LinearGradient(
                gradient: Gradient(colors: [
                    .clear,
                    palette.textPrimary.opacity(0.9),
                    .clear
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: bandWidth)
            .offset(x: x)
        }
        .mask(text)
        .allowsHitTesting(false)
    }

    // MARK: - Palette / beam

    private var palette: ChatPalette {
        ChatPalette(
            colorScheme: colorScheme,
            backgroundStyle: ChatBackgroundStyle.storedValue(backgroundStyleRawValue),
            temperature: ChatPaletteTemperature.storedValue(paletteTemperatureRawValue)
        )
    }

    private var resolvedBeam: ResolvedBeam {
        ActivityBeamStyle.storedValue(beamStyleRawValue).resolved(
            palette: palette,
            colorScheme: colorScheme,
            accent: HeaderLogoColor.color(for: headerLogoColorHex)
        )
    }

    private var beamStyle: BeamStyle {
        var style = BeamStyle(resolved: resolvedBeam)
        if !entranceBoost && !finaleSweep {
            style.strength *= 0.6
        }
        return style
    }

    private func accessibilityText(displayLabel: String) -> String {
        isActive
            ? String(localized: "\(displayLabel), in progress")
            : String(localized: "\(displayLabel), finished")
    }
}

/// Background, hairline, beam, and hit shape for the capsule. At
/// accessibility type sizes the pill becomes a continuous rounded rectangle
/// so a two-line wrapped label doesn't fight the capsule geometry. Two
/// explicit branches keep `borderBeam`'s generic `InsettableShape` parameter
/// happy without shape erasure.
private struct CapsuleChrome: ViewModifier {
    let palette: ChatPalette
    let beamStyle: BeamStyle
    let beamActive: Bool
    let usesAccessibilityLayout: Bool

    func body(content: Content) -> some View {
        if usesAccessibilityLayout {
            content
                .background(shapeAccessibility.fill(palette.surface.opacity(0.8)))
                .overlay(shapeAccessibility.strokeBorder(palette.tableRule, lineWidth: 1))
                .borderBeam(style: beamStyle, shape: shapeAccessibility, active: beamActive)
                .contentShape(shapeAccessibility)
        } else {
            content
                .background(Capsule().fill(palette.surface.opacity(0.8)))
                .overlay(Capsule().strokeBorder(palette.tableRule, lineWidth: 1))
                .borderBeam(style: beamStyle, shape: Capsule(), active: beamActive)
                .contentShape(Capsule())
        }
    }

    private var shapeAccessibility: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }
}

#if DEBUG
#Preview("Activity capsules") {
    VStack(alignment: .leading, spacing: 16) {
        ActivityCapsuleView(
            orbState: .working,
            label: "Thinking…",
            isActive: true
        )
        ActivityCapsuleView(
            orbState: .searching,
            label: "Reading ChatPalette.swift",
            isActive: true
        )
        ActivityCapsuleView(
            orbState: .working,
            label: "Thinking…",
            isActive: false,
            completedIcon: "brain",
            completedLabel: "Thought for 12s"
        )
    }
    .padding(24)
}
#endif
