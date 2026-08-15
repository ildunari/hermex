import SwiftUI

/// Stable identities for the interactive status surfaces docked above the composer.
///
/// A single selection owns expansion so adding a delegate/subagent surface later
/// cannot produce overlapping cards: opening one surface closes the previous one.
enum ComposerStatusSurfaceID: Hashable {
    case plan
    case goal
    case subagents
}

/// Shared spacing for every expanded composer surface.
///
/// Feature views provide their own semantic content, but the card owns its insets
/// so the first row never sits against the glass edge and future surfaces do not
/// each invent subtly different padding.
enum ComposerStatusSurfaceMetrics {
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 14
    static let bottomPadding: CGFloat = 14
    static let collapsedCornerRadius: CGFloat = 19
    static let expandedCornerRadius = ActivityBlockChrome.cornerRadius
    static let railSpacing: CGFloat = 8
    static let semanticIconSize: CGFloat = 13
}

/// Horizontally scrolling home for composer status pills and their expanded cards.
///
/// Children keep their readable intrinsic width. A couple of compact pills fit
/// naturally; once more surfaces are added, the rail scrolls instead of crushing
/// labels or wrapping into a second row above the composer.
struct ComposerStatusSurfaceRail<Content: View>: View {
    var expandedSurface: ComposerStatusSurfaceID?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if expandedSurface == nil {
                ScrollView(.horizontal) {
                    surfaceRow
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled(false)
                .defaultScrollAnchor(.center, for: .alignment)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Only one surface is rendered while expanded. Do not leave it
                // inside the collapsed pill rail's horizontal ScrollView: that
                // second scroll recognizer competes with the card's vertical
                // ScrollView and can swallow taps intended for its canvas.
                // Mounting the card directly restores descendant taps and keeps
                // vertical scrolling independent for plan, goal, and future
                // composer status surfaces.
                surfaceRow
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session status")
        .accessibilityIdentifier(ActivityAccessibilityID.composerStatusRail)
    }

    private var surfaceRow: some View {
        HStack(alignment: .bottom, spacing: ComposerStatusSurfaceMetrics.railSpacing) {
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal)
    }

    init(
        expandedSurface: ComposerStatusSurfaceID? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.expandedSurface = expandedSurface
        self.content = content
    }
}

private struct ComposerStatusSurfaceModifier: ViewModifier {
    let isExpanded: Bool
    let palette: ChatPalette
    let beamStyle: BeamStyle
    let beamActive: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: isExpanded
                ? ComposerStatusSurfaceMetrics.expandedCornerRadius
                : ComposerStatusSurfaceMetrics.collapsedCornerRadius,
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        content
            // Keep the compact pill visually quiet while preserving Apple's
            // minimum comfortable touch target for every current/future surface.
            .frame(minHeight: 44)
            .background(
                shape
                    .fill(palette.surface.opacity(0.5))
                    .overlay(shape.strokeBorder(palette.tableRule, lineWidth: 1))
            )
            .adaptiveGlass(
                .regular,
                isInteractive: false,
                fallbackMaterial: .regularMaterial,
                in: shape
            )
            .clipShape(shape)
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12),
                radius: 8,
                y: 3
            )
            .borderBeam(
                style: beamStyle,
                shape: shape,
                active: beamActive
            )
    }
}

extension View {
    /// Applies the shared morphing pill/card chrome used by composer surfaces.
    func composerStatusSurface(
        isExpanded: Bool,
        palette: ChatPalette,
        beamStyle: BeamStyle,
        beamActive: Bool
    ) -> some View {
        modifier(
            ComposerStatusSurfaceModifier(
                isExpanded: isExpanded,
                palette: palette,
                beamStyle: beamStyle,
                beamActive: beamActive
            )
        )
    }
}
