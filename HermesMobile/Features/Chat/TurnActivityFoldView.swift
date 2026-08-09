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
/// layer smear), and flickers on insertion inside eager stacks.
///
/// **Why the blocks tree unmounts when folded.** An earlier version kept both
/// trees mounted and cross-faded opacity inside a clipped, fixed-height
/// container. That made every settled turn keep its full block list alive —
/// for a 70-tool turn, seventy rows laying out behind a 40pt window — which
/// made expanding and collapsing visibly janky. Folded renders the summary
/// row *only*; the blocks mount on expand and the height animates naturally.
///
/// **Why the summary row stays mounted while expanded.** It used to be
/// replaced by the blocks, so tapping destroyed one full-width row and
/// produced two content-width capsules in its place, with the chevron
/// relocating to the opposite corner. Nothing connected the two states, so the
/// disclosure read as a swap rather than an opening. The row is now a
/// persistent header: it stays put, keeps owning the chevron, and the blocks
/// reveal *underneath* it. Only the blocks subtree mounts and unmounts, so the
/// 70-tool cost above is unchanged.
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
    @State private var didAppear = false
    /// Bumped to carry an explicit animation transaction when the automatic
    /// fold flips; `isFolded` is derived, so it needs a driver to animate.
    @State private var foldTick = 0
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
    }

    /// Whether the fold is currently showing the summary row.
    private var isFolded: Bool {
        userExpanded.map { !$0 } ?? (initiallyCollapsed || isCollapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always mounted, in both states. This is the anchor that makes the
            // disclosure legible: the thing you tap does not move or vanish.
            summary(!isFolded) { setUserExpanded(isFolded) }

            if !isFolded {
                blocks()
                    .padding(.top, Self.blocksTopInset)
                    // Same anchored reveal the cards use, so the fold and the
                    // blocks inside it read as one motion rather than two
                    // curves competing.
                    .transition(ChatMotion.cardContentTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Clip the frame that actually animates.
        //
        // The inserted blocks are laid out at full final size on frame one
        // while only this VStack's height interpolates, so for the length of
        // the spring the activity content draws *over* the answer below it —
        // two markdown layers ghosting through each other. The blocks got the
        // same fix one level down, but inside the fold they mount already
        // expanded, so clipping them to their own bounds clips nothing; the
        // fold's frame is the one that moves.
        .clipped()
        .onAppear { didAppear = true }
        .onChange(of: isCollapsed) { _, collapsed in
            // An explicit user choice outranks the automatic fold.
            guard userExpanded == nil, didAppear else { return }
            guard animatesFold, !reduceMotion else { return }
            // The fold itself is driven by `isFolded`; animate the swap.
            withAnimation(foldAnimation) {
                foldTick += 1
            }
        }
    }

    private func setUserExpanded(_ expanded: Bool) {
        guard !reduceMotion else {
            userExpanded = expanded
            return
        }
        withAnimation(foldAnimation) {
            userExpanded = expanded
        }
    }

    /// Matches the transcript's disclosure curve so opening a turn's activity
    /// feels like opening any other card in the timeline.
    private var foldAnimation: Animation? { TurnActivityFoldAnimation.curve(reduceMotion: reduceMotion) }

    /// Gap between the header row and the revealed blocks. Matches the spacing
    /// between the blocks themselves so the header reads as the first item in
    /// one stack rather than a separate object sitting above it.
    private static var blocksTopInset: CGFloat { 8 }
}

/// Non-generic holder: static stored properties aren't allowed in generic types.
enum TurnActivityFoldAnimation {
    /// Deliberately the same container spring the cards use
    /// (`ChatMotion.cardExpand`). The fold and the blocks inside it used to run
    /// on unrelated curves at the same time, which is what made expanding a
    /// settled turn feel like several things happening at once.
    static func curve(reduceMotion: Bool) -> Animation? {
        ChatMotion.cardExpand(reduceMotion: reduceMotion)
    }
}
