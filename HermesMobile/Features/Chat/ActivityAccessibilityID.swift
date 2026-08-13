import Foundation

/// Accessibility identifiers for the turn-activity and plan surfaces.
///
/// These exist for UI tests, not for VoiceOver — the surfaces already carry
/// spoken labels. Identifiers are needed because those labels are *dynamic*
/// ("Thought for 3.4s · ran 56 tools", "4 of 20"), so a test cannot address
/// the element by text without asserting on content it does not care about.
///
/// Kept in the app target (not the test target) so the identifier and its use
/// site live together and cannot drift apart silently.
enum ActivityAccessibilityID {
    /// The collapsed one-line summary of a settled turn's activity.
    static let turnSummaryRow = "activity.turn-summary-row"
    /// The thinking block's header capsule, inside the merged card.
    static let thinkingHeader = "activity.thinking-header"
    /// The thinking block's revealed markdown body.
    static let thinkingBody = "activity.thinking-body"
    /// Opens a dedicated reader for reasoning that exceeds the inline preview.
    static let thinkingReadFullButton = "activity.thinking-read-full"
    /// The dedicated, independently scrolling reasoning reader.
    static let thinkingFullReader = "activity.thinking-full-reader"
    /// The tool block's header capsule.
    static let toolsHeader = "activity.tools-header"
    /// The capped, scrollable tool-runs list.
    static let toolRunsScroll = "activity.tool-runs-scroll"
    /// The plan pill / expanded card header above the composer.
    static let planHeader = "plan.header"
    /// The plan's bounded, scrollable checklist.
    static let planRowsScroll = "plan.rows-scroll"
}
