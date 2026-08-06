import SwiftUI

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
    @AppStorage(ChatBackgroundStyle.storageKey) private var backgroundStyleRawValue = ChatBackgroundStyle.defaultValue.rawValue
    @AppStorage(ChatPaletteTemperature.storageKey) private var paletteTemperatureRawValue = ChatPaletteTemperature.defaultValue.rawValue
    @AppStorage(ActivityBeamStyle.storageKey) private var beamStyleRawValue = ActivityBeamStyle.defaultValue.rawValue
    @AppStorage(HeaderLogoColor.storageKey) private var headerLogoColorHex = HeaderLogoColor.defaultHex

    /// True during the two-sweep entrance right after activation; the beam
    /// then settles to reduced strength while work continues.
    @State private var entranceBoost = false

    var body: some View {
        let displayLabel = isActive ? label : (completedLabel ?? label)

        Button {
            onTap?()
        } label: {
            HStack(spacing: 8) {
                if isActive {
                    ThinkingOrbView(state: orbState, size: 20, color: .secondary)
                } else {
                    Image(systemName: completedIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(completedIconColor ?? palette.textSecondary)
                        .frame(width: 20, height: 20)
                }

                labelText(displayLabel)

                if let accessory {
                    accessory
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(palette.surface.opacity(0.8)))
            .overlay(Capsule().strokeBorder(palette.tableRule, lineWidth: 1))
            .borderBeam(
                style: beamStyle,
                shape: Capsule(),
                active: isActive && beamStyle.isVisible
            )
            .contentShape(Capsule())
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
    }

    // MARK: - Label

    @ViewBuilder
    private func labelText(_ value: String) -> some View {
        let styled = Text(value).font(AppFont.subheadline())
        let base = styled
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(palette.textSecondary)

        if isActive && !reduceMotion {
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
        if !entranceBoost {
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
