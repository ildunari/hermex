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
}

/// Horizontally scrolling home for composer status pills and their expanded cards.
///
/// Children keep their readable intrinsic width. A couple of compact pills fit
/// naturally; once more surfaces are added, the rail scrolls instead of crushing
/// labels or wrapping into a second row above the composer.
struct ComposerStatusSurfaceRail<Content: View>: View {
    var expandedSurface: ComposerStatusSurfaceID?
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                surfaceRow
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            // Collapsed pills own separate shadows. Clipping the scroll view
            // sliced those shadows at a hard vertical edge and made adjacent
            // pills read as one shared floating slab.
            .scrollClipDisabled(true)
            .defaultScrollAnchor(.center, for: .alignment)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: expandedSurface, initial: true) { _, surface in
                guard let surface else { return }
                // Keep the same scroll/content identity while the selected
                // pill grows. Replacing the ScrollView with a second branch
                // made SwiftUI insert the card from the dock's bottom edge
                // instead of morphing outward from the tapped pill.
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(ChatMotion.cardChrome(reduceMotion: reduceMotion)) {
                        proxy.scrollTo(surface, anchor: .center)
                    }
                }
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
                color: .black.opacity(
                    colorScheme == .dark
                        ? (isExpanded ? 0.34 : 0.22)
                        : (isExpanded ? 0.12 : 0.08)
                ),
                radius: isExpanded ? 8 : 3,
                y: isExpanded ? 3 : 1.5
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
