import SwiftUI

/// Folds a turn's activity blocks (thinking + tool runs) into a single summary
/// row once the assistant's answer starts streaming.
///
/// **Why it folds at the first answer token, not at turn end.** When the stream
/// finishes, the live views are torn down and rebuilt from reconciled session
/// data with different identities, so any animation still running across that
/// boundary dies mid-flight and pops. Folding on the first token completes the
/// motion seconds before reconcile; reconcile then swaps a settled collapsed
/// row for a visually identical one, which reads as nothing happening.
/// Historical rendering therefore mounts *directly* collapsed — see
/// `initiallyCollapsed`.
///
/// **Why not `matchedGeometryEffect`.** It has no N-sources-to-one-target
/// mode, interpolates frames rather than content (text and the composited beam
/// layer smear), and flickers on insertion inside eager stacks. Instead both
/// trees stay mounted and only container height plus opacity animate, with the
/// container top-anchored and clipped so the blocks visually fold up into the
/// summary row.
struct TurnActivityFoldView<Blocks: View, Summary: View>: View {
    /// Drives the fold. Set true when the first answer token lands.
    let isCollapsed: Bool
    /// True for reconciled/historical turns, which must appear already folded
    /// with no animation at all.
    var initiallyCollapsed: Bool = false
    /// Suppress the animation when the reader has scrolled away from the
    /// bottom: there is nothing to watch, and animating off-screen is waste.
    var animatesFold: Bool = true
    @ViewBuilder let blocks: () -> Blocks
    /// Receives the current expansion state and the toggle action, so the
    /// summary row can show the right chevron and be tappable.
    @ViewBuilder let summary: (Bool, @escaping () -> Void) -> Summary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var foldProgress: Double
    @State private var didAppear = false
    /// User override. `nil` follows the automatic fold; set explicitly once the
    /// reader taps the summary (open) or the block header (re-collapse), so a
    /// settled turn's details stay reachable rather than being sealed shut.
    @State private var userExpanded: Bool?

    init(
        isCollapsed: Bool,
        initiallyCollapsed: Bool = false,
        animatesFold: Bool = true,
        @ViewBuilder blocks: @escaping () -> Blocks,
        @ViewBuilder summary: @escaping (Bool, @escaping () -> Void) -> Summary
    ) {
        self.isCollapsed = isCollapsed
        self.initiallyCollapsed = initiallyCollapsed
        self.animatesFold = animatesFold
        self.blocks = blocks
        self.summary = summary
        // Seed the state directly rather than correcting it in `onAppear`,
        // which flashes one expanded frame when a historical row mounts.
        _foldProgress = State(initialValue: (initiallyCollapsed || isCollapsed) ? 1 : 0)
    }

    /// Whether the fold is currently showing the summary row.
    private var isFolded: Bool {
        userExpanded.map { !$0 } ?? (initiallyCollapsed || isCollapsed)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            summary(false) { setUserExpanded(true) }
                .opacity(foldProgress)
                .accessibilityHidden(foldProgress < 0.5)

            blocks()
                .opacity(1 - foldProgress)
                .accessibilityHidden(foldProgress >= 0.5)
                // Re-collapse affordance while expanded, so the fold is a
                // real two-way disclosure rather than a one-shot.
                .overlay(alignment: .topTrailing) {
                    if userExpanded == true {
                        Button {
                            setUserExpanded(false)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Collapse activity"))
                    }
                }
        }
        .frame(height: foldProgress >= 1 ? summaryHeight : nil, alignment: .top)
        .clipped()
        .onAppear {
            didAppear = true
        }
        .onChange(of: isCollapsed) { _, collapsed in
            // An explicit user choice outranks the automatic fold.
            guard userExpanded == nil else { return }
            guard didAppear else {
                foldProgress = collapsed ? 1 : 0
                return
            }
            guard animatesFold, !reduceMotion else {
                foldProgress = collapsed ? 1 : 0
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                foldProgress = collapsed ? 1 : 0
            }
        }
    }

    private func setUserExpanded(_ expanded: Bool) {
        userExpanded = expanded
        guard !reduceMotion else {
            foldProgress = expanded ? 0 : 1
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            foldProgress = expanded ? 0 : 1
        }
    }

    /// Deterministic one-line height; measuring at runtime would introduce a
    /// layout pass mid-animation, which is exactly what makes this pop. Scaled
    /// with the type size so accessibility sizes don't clip the row.
    @ScaledMetric(relativeTo: .footnote) private var scaledSummaryHeight: CGFloat = 40

    private var summaryHeight: CGFloat { scaledSummaryHeight }
}
