import SwiftUI

enum ChatMotion {
    static func press(duration: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: duration, extraBounce: 0)
    }

    static func quickState(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.10) : .easeInOut(duration: 0.16)
    }

    static func disclosure(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.10) : .smooth(duration: 0.18, extraBounce: 0)
    }

    // MARK: - Card disclosure
    //
    // Expanding an activity card is two motions, not one. The container's
    // height is the "panel" and gets a spring in the 200–500ms drawer budget;
    // the contents are a quick fade that starts *after* the container has room
    // to hold them. Driving both from a single 0.18s curve (what
    // `disclosure` does) is why everything used to land on the same frame.

    /// The container growing or shrinking. Owns the layout change.
    static func cardExpand(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.34, bounce: 0.12)
    }

    /// Contents fading in once the container has opened. Deliberately shorter
    /// than `cardExpand` so the text settles before the height finishes.
    static func cardContent(reduceMotion: Bool, delay: Double = 0) -> Animation? {
        if reduceMotion {
            return .easeOut(duration: 0.10)
        }
        return .easeOut(duration: 0.16).delay(delay)
    }

    /// Per-row delay so an expanded card populates from the top down instead of
    /// appearing all at once.
    ///
    /// Capped deliberately: a 70-tool block staggered row-by-row would take
    /// seconds to finish reading as "still loading". The first few rows carry
    /// the sense of the card filling; everything after arrives together.
    static func cardRowDelay(index: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        let step = 0.035
        let maxStaggeredRows = 6
        return Double(min(index, maxStaggeredRows)) * step
    }

    /// Head start before contents begin arriving, so they emerge from inside
    /// the opening card rather than racing its top edge.
    static let cardContentLeadIn: Double = 0.06

    static func composerChrome(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.22, extraBounce: 0)
    }

    static func scrollToLatest(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.20)
    }

    /// Bottom-follow scrolling and active-row height growth while a response
    /// streams in. Short enough to keep up with the ~48ms word-reveal cadence;
    /// each new flush retargets the previous animation so the streaming edge
    /// glides instead of stepping per flush.
    static func streamingFollow(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    static func typingIndicator(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    }

    static func bottomOverlayTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    static func disclosureTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    /// Transition for content revealed inside an expanding card.
    ///
    /// Explicitly **not** `.move(edge: .top)`: that slides content in from the
    /// container's top edge while the container is still only a few points
    /// tall, so the content visibly flies down through the card from above it.
    /// Scaling from a `.top` anchor expands the content downward from where the
    /// card actually opens, which is what "populating from within" means.
    static func cardContentTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
    }
}
