import SwiftUI

struct ReasoningBlockView: View {
    let text: String
    var isStreaming: Bool = false
    /// How long the reasoning step took, when known (wired from
    /// ChatTranscriptView). Drives the "Thought for 3.4s" completed label;
    /// nil keeps the plain "Thought".
    var completedDuration: TimeInterval? = nil
    /// When embedded in a merged activity card the parent owns the container,
    /// so the block must not draw its own.
    var drawsOwnChrome: Bool = true
    /// Default expansion when the reader has not toggled this block.
    ///
    /// Production always passes nil now — the merged card's sections open as
    /// collapsed pills that follow the user's `thinkingCardsStartExpanded`
    /// setting, the same as standalone blocks. Mounting them open was tried
    /// and reverted: the fold inserts its subtree with an opacity transition,
    /// so a pre-expanded markdown body pops in at full height instead of
    /// revealing inline (the pill's own tap animates correctly because its
    /// clipped frame interpolates). Debug galleries still pass `true` to
    /// render the expanded treatment directly.
    var startsExpandedOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChatBackgroundStyle.storageKey) private var backgroundStyleRawValue = ChatBackgroundStyle.defaultValue.rawValue
    @AppStorage(ChatPaletteTemperature.storageKey) private var paletteTemperatureRawValue = ChatPaletteTemperature.defaultValue.rawValue
    @AppStorage(ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey) private var startsExpanded = false
    @State private var userToggledExpansion: Bool?

    private var isExpanded: Bool {
        #if DEBUG
        // Debug motion lab drives expansion on a timer so open/close can be
        // recorded deterministically; nil in every production path.
        if let forced = disclosureLabExpansion { return forced }
        #endif
        return ChatTranscriptDisplaySettings.isCardExpanded(
            userToggled: userToggledExpansion,
            startsExpanded: startsExpandedOverride ?? startsExpanded
        )
    }

    #if DEBUG
    @Environment(\.disclosureLabExpansion) private var disclosureLabExpansion
    #endif

    var body: some View {
        if let trimmedText {
            let presentedText = ReasoningMarkdownPresentation.formatted(trimmedText)
            VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
                // `isStreaming` is fed from `ChatViewModel.isReasoningPhaseActive`
                // at the live call sites (ChatTranscriptView): the orb/beam
                // animate for the entire reasoning *step* — including long
                // pauses between reasoning deltas — and settle only when the
                // turn semantically moves on (tool call, answer text, or end).
                ActivityCapsuleView(
                    orbState: .thinking,
                    label: String(localized: "Thinking…"),
                    isActive: isStreaming,
                    completedIcon: "brain",
                    completedLabel: completedLabelText,
                    accessory: AnyView(chevron),
                    onTap: {
                        withAnimation(ChatMotion.cardExpand(reduceMotion: reduceMotion)) {
                            userToggledExpansion = !isExpanded
                        }
                    },
                    // Expanded, the block itself is the bordered container, so
                    // the header must not draw a competing pill inside it.
                    chrome: isExpanded ? .none : .pill
                )
                .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand details.")
                // Stable handle for UI tests; the label carries a duration.
                .accessibilityIdentifier(ActivityAccessibilityID.thinkingHeader)

                if isExpanded {
                    // Quiet indented body: a thin rail with the thought hanging
                    // off it, matching the expanded tool block rather than
                    // nesting a washed slab inside a card.
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(palette.tableRule)
                            .frame(width: 2)

                        // Paragraph-by-paragraph reveal so the thought fills the
                        // card top-down, the same way tool rows do. Each block is
                        // laid out in its final position from frame one and only
                        // fades up — nothing travels into place.
                        VStack(alignment: .leading, spacing: 6) {
                            // One renderer for the whole thought rather than one
                            // per paragraph: markdown blocks span paragraph
                            // breaks (lists, fences), so splitting first would
                            // parse each fragment out of context and break every
                            // multi-line construct. That also means the reveal is
                            // one fade rather than a per-paragraph stagger.
                            MarkdownRenderer(
                                content: presentedText,
                                isStreaming: isStreaming,
                                typographyRole: .reasoning
                            )
                            // Report full intrinsic height on the first layout
                            // pass. Without this the renderer settles its height
                            // over a frame or two *while* the card's own height
                            // spring is running, so the text is laid out against
                            // a moving container and visibly slides.
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.leading, 4)
                    // Owns its fade timing; see `cardBodyRevealTransition` —
                    // inheriting the delayed height spring painted the full
                    // thought before the window opened.
                    .transition(ChatMotion.cardBodyRevealTransition(reduceMotion: reduceMotion))
                    // Lets a UI test assert the thought body actually mounted,
                    // rather than inferring it from the header's chevron.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(ActivityAccessibilityID.thinkingBody)
                }
            }
            // One container for the whole block when open — same treatment the
            // tool block uses, so thinking and tools read as one family.
            .modifier(ReasoningBlockChrome(
                palette: palette,
                isExpanded: isExpanded,
                drawsSurface: drawsOwnChrome,
                reduceMotion: reduceMotion
            ))
            // Clip to the animating shape.
            //
            // The body reports its full intrinsic height on the frame it
            // mounts, but the card's height spring is still near zero, so
            // without clipping the text renders at full size *outside* the
            // card and overlaps whatever sits below it. That overspill sliding
            // up into place is the "flying in from the top" artifact — it was
            // masked while the body was plain `Text` (cheap, short) and became
            // obvious once markdown made the body taller and multi-block.
            .clipShape(ActivityBlockChrome.shape())
            .frame(maxWidth: .infinity, alignment: .leading)
            // Pre-warm the math-segmentation layout while the block is still a
            // collapsed pill. The scan is the only meaningful cost inside the
            // expand tap's commit (~16ms debug / ~5ms release for a 5KB
            // thought, cache-cold), and it lands inside `cardExpand`'s 0.12s
            // lead-in — eating the spring's first frames on the first open
            // after a cold launch. Warming here (mount time, off-main, settled
            // text only) makes the tap a guaranteed cache hit. `NSCache` is
            // thread-safe, and the pill mounts at least an animation-length
            // before any finger can reach it.
            .task(id: isStreaming ? nil : presentedText) {
                guard !isStreaming, !isExpanded else { return }
                let text = presentedText
                await Task.detached(priority: .utility) {
                    _ = MarkdownMathLayoutCache.layout(for: text)
                }.value
            }
        }
    }

    private var completedLabelText: String {
        guard let completedDuration else {
            return String(localized: "Thought")
        }
        return String(localized: "Thought for \(ActivityDurationFormat.string(completedDuration))")
    }

    private var palette: ChatPalette {
        ChatPalette(
            colorScheme: colorScheme,
            backgroundStyle: ChatBackgroundStyle.storedValue(backgroundStyleRawValue),
            temperature: ChatPaletteTemperature.storedValue(paletteTemperatureRawValue)
        )
    }

    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var trimmedText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Presentation-only normalization for provider reasoning ledgers.
///
/// Several providers emit progress as consecutive standalone `**bold**` lines.
/// CommonMark treats a single newline as a soft break, so those lines collapse
/// into one dense paragraph. Only runs of two or more exact bold-only lines are
/// recognized here: they receive hard line breaks and a thematic rule at the
/// boundary to adjacent prose/ledger blocks. Ordinary emphasis, real headings,
/// lists, and fenced code retain their original Markdown semantics.
enum ReasoningMarkdownPresentation {
    static func formatted(_ content: String) -> String {
        let blocks = markdownBlocks(in: content)
        guard blocks.contains(where: \.isStatusLedger) else { return content }

        return blocks.enumerated().map { index, block in
            let rendered = block.isStatusLedger
                ? block.lines.joined(separator: "  \n")
                : block.lines.joined(separator: "\n")
            guard index > 0 else { return rendered }

            let previous = blocks[index - 1]
            let separator = previous.isStatusLedger || block.isStatusLedger
                ? "\n\n---\n\n"
                : "\n\n"
            return separator + rendered
        }.joined()
    }

    private static func markdownBlocks(in content: String) -> [Block] {
        var blocks: [Block] = []
        var currentLines: [String] = []
        var isInsideFence = false

        func flushCurrentBlock() {
            guard !currentLines.isEmpty else { return }
            blocks.append(Block(lines: currentLines))
            currentLines = []
        }

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFenceDelimiter(trimmed) {
                currentLines.append(line)
                isInsideFence.toggle()
            } else if !isInsideFence, trimmed.isEmpty {
                flushCurrentBlock()
            } else {
                currentLines.append(line)
            }
        }
        flushCurrentBlock()
        return blocks
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    private struct Block {
        let lines: [String]

        var isStatusLedger: Bool {
            lines.count >= 2 && lines.allSatisfy(Self.isStandaloneBoldLine)
        }

        private static func isStandaloneBoldLine(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 4,
                  trimmed.hasPrefix("**"),
                  trimmed.hasSuffix("**")
            else { return false }

            let inner = trimmed.dropFirst(2).dropLast(2)
                .trimmingCharacters(in: .whitespaces)
            return !inner.isEmpty && !inner.contains("**")
        }
    }
}

/// Shared container geometry for expanded activity blocks (thinking + tools).
///
/// 10pt continuous matches `MarkerMessageCardView` and the timeline accessory
/// surface, so an expanded block reads as the same family of card as the rest
/// of the transcript instead of an oversized pill.
enum ActivityBlockChrome {
    static let cornerRadius: CGFloat = 10

    static func shape() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    // MARK: - Header alignment
    //
    // Expanding a block wraps the *same* header in a padded container, so the
    // header would shift down and right by exactly the padding it gained. The
    // two paddings below are chosen to cancel the capsule's own inset, keeping
    // the orb and title pinned while the card grows around them:
    //
    //   collapsed  header x = capsule 14                     = 14
    //   expanded   header x = block 12 + capsule 2           = 14
    //   collapsed  header y = capsule 7                      = 7
    //   expanded   header y = block 7 (top) + capsule 0      = 7
    //
    // Bottom padding is free to be larger — nothing below it needs to align.

    /// Horizontal inset the expanded container adds.
    static let horizontalPadding: CGFloat = 12
    /// Top inset, matched to the collapsed capsule's vertical padding so the
    /// header does not drop when the card opens.
    static let topPadding: CGFloat = 7
    static let bottomPadding: CGFloat = 10

    /// Capsule padding while it is a block header (chrome `.none`), reduced to
    /// absorb the container's inset. See the arithmetic above.
    static let headerCapsuleHorizontalPadding: CGFloat = 2
    static let headerCapsuleVerticalPadding: CGFloat = 0
}

/// One border for an expanded thinking block. Collapsed, the header capsule
/// keeps its own pill chrome and this fades out.
///
/// Deliberately a **single** branch. An `if isEnabled { ... } else { content }`
/// modifier gives SwiftUI two different view identities, so toggling it
/// *replaces* the subtree instead of animating it — which is what produced the
/// ghosted double-capsule during expansion. Here the chrome always wraps the
/// same content and only its values animate.
private struct ReasoningBlockChrome: ViewModifier {
    let palette: ChatPalette
    /// Whether the block is open. Owns the *padding*, which must apply even
    /// when the parent draws the surface: the header capsule sheds its own
    /// 14/7 inset on expand (`.pill` → `.none`), and this padding is what
    /// replaces it. Keying padding to `drawsSurface` instead made the header
    /// jump 12pt left and 7pt up whenever the block was inside a container.
    let isExpanded: Bool
    /// Whether this block draws its own fill and border. False when it is a
    /// section inside `ActivityContainerView`, which owns the surface.
    let drawsSurface: Bool
    /// Phase-1 curve for the chrome itself; the height rides `cardExpand`.
    var reduceMotion: Bool = false

    func body(content: Content) -> some View {
        // Single branch with animatable opacity, never an if/else on the styled
        // view: two identities make SwiftUI replace the subtree rather than
        // animate it.
        let showsSurface = isExpanded && drawsSurface
        content
            .padding(.horizontal, isExpanded ? ActivityBlockChrome.horizontalPadding : 0)
            .padding(.top, isExpanded ? ActivityBlockChrome.topPadding : 0)
            .padding(.bottom, isExpanded ? ActivityBlockChrome.bottomPadding : 0)
            .background(
                ActivityBlockChrome.shape()
                    .fill(palette.surface.opacity(0.8))
                    .opacity(showsSurface ? 1 : 0)
            )
            .overlay(
                ActivityBlockChrome.shape()
                    .strokeBorder(palette.tableRule, lineWidth: 1)
                    .opacity(showsSurface ? 1 : 0)
            )
            // Chrome resolves on the short horizontal curve; the enclosing
            // `withAnimation(cardExpand)` still owns the height.
            .animation(ChatMotion.cardChrome(reduceMotion: reduceMotion), value: showsSurface)
    }
}
