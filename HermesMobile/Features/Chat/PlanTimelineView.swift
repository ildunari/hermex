import SwiftUI

/// The agent's plan, as a collapsed progress pill that opens into a checklist.
///
/// Sits above the composer rather than inside the transcript, because
/// `todo_state` is session state and not turn history — the server re-sends the
/// whole list on every write, so a transcript-embedded card would stack a stale
/// copy per update. One pinned surface, always showing the latest snapshot.
struct PlanTimelineView: View {
    let state: TodoState
    @Binding var isExpanded: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ChatBackgroundStyle.storageKey) private var backgroundStyleRawValue = ChatBackgroundStyle.defaultValue.rawValue
    @AppStorage(ChatPaletteTemperature.storageKey) private var paletteTemperatureRawValue = ChatPaletteTemperature.defaultValue.rawValue
    @AppStorage(ActivityBeamStyle.storageKey) private var beamStyleRawValue = ActivityBeamStyle.defaultValue.rawValue
    @AppStorage(HeaderLogoColor.storageKey) private var headerLogoColorHex = HeaderLogoColor.defaultHex

    /// Drives phase 1 of the reveal (chrome) independently of the row fades, so
    /// the container widens before its contents arrive. See `ChatMotion`.
    @State private var chromeExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                rows
                    .padding(.horizontal, ActivityBlockChrome.horizontalPadding)
                    .padding(.top, ActivityBlockChrome.topPadding)
                    .padding(.bottom, ActivityBlockChrome.bottomPadding)
            }

            header
        }
        // Hugs its content instead of filling the transcript width. A plan is a
        // short list of short lines; a full-width slab over the composer reads
        // as a sheet rather than an inline status surface. The cap is enforced
        // on the row labels (see `PlanRowLabel`), so the card ends up as wide as
        // its longest *wrapped* row rather than its longest ideal one.
        .fixedSize(horizontal: true, vertical: false)
        .background(
            // Single branch with an animatable opacity rather than an
            // if/else on the styled view: two view identities make SwiftUI
            // *replace* the subtree instead of animating it, which shows up as
            // a ghosted double-card during the reveal.
            ActivityBlockChrome.shape()
                .fill(palette.surface.opacity(chromeExpanded ? 0.5 : 0.0))
                .overlay(
                    ActivityBlockChrome.shape()
                        .strokeBorder(palette.tableRule, lineWidth: 1)
                        .opacity(chromeExpanded ? 1 : 0)
                )
        )
        // Glass sits over the tinted fill, not instead of it: the fill keeps the
        // palette's warmth, glass supplies the blur and specular edge. Matches
        // how `ChatActiveRunStatusView` layers the same two.
        .adaptiveGlass(
            .regular,
            isInteractive: false,
            fallbackMaterial: .regularMaterial,
            in: ActivityBlockChrome.shape()
        )
        .clipShape(ActivityBlockChrome.shape())
        // The beam marks the card as live while it is open — the same signal the
        // thinking and tool blocks use, so the plan reads as one of that family.
        .borderBeam(
            style: beamStyle,
            shape: ActivityBlockChrome.shape(),
            active: chromeExpanded && beamStyle.isVisible
        )
        .onChange(of: isExpanded) { _, expanded in
            withAnimation(ChatMotion.cardChrome(reduceMotion: reduceMotion)) {
                chromeExpanded = expanded
            }
        }
        .onAppear { chromeExpanded = isExpanded }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Collapsed pill

    private var header: some View {
        Button {
            withAnimation(ChatMotion.cardExpand(reduceMotion: reduceMotion)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                progressGlyph

                Text(progressLabel)
                    .font(AppFont.footnote())
                    .foregroundStyle(palette.textSecondary)
                    // Rolls the digit instead of hard-cutting when a step
                    // completes. This pill is on screen for the whole run, so
                    // it is the counter the user actually watches.
                    .contentTransition(.numericText(value: Double(state.currentStep)))
                    .lineLimit(1)
            }
            // Roomier than a status chip: the pill is the resting state of this
            // surface, so it reads as a control rather than a label. No chevron
            // — the whole pill is the hit target, and the affordance is the
            // floating shape itself.
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                // The pill keeps its own chrome only while collapsed; expanded,
                // the surrounding card owns the surface so the two don't stack.
                Capsule(style: .continuous)
                    .fill(palette.surface.opacity(chromeExpanded ? 0 : 0.5))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(palette.tableRule, lineWidth: 1)
                            .opacity(chromeExpanded ? 0 : 1)
                    )
            )
            .adaptiveGlass(
                .regular,
                isInteractive: false,
                fallbackMaterial: .regularMaterial,
                in: Capsule(style: .continuous)
            )
            // Lifts the pill off the transcript so it reads as floating above
            // the composer rather than printed onto the canvas. Only while
            // collapsed: once expanded the card owns the elevation, and two
            // stacked shadows muddy the edge.
            .shadow(
                color: .black.opacity(chromeExpanded ? 0 : (colorScheme == .dark ? 0.34 : 0.12)),
                radius: chromeExpanded ? 0 : 8,
                y: chromeExpanded ? 0 : 3
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isExpanded ? "Double tap to collapse the plan." : "Double tap to expand the plan.")
    }

    @ViewBuilder
    private var progressGlyph: some View {
        if state.isFinished {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.green.opacity(0.85))
        } else {
            PlanProgressRing(
                fraction: completionFraction,
                reduceMotion: reduceMotion,
                // Accent-tinted rather than gray: in the collapsed pill the ring
                // is the only live element, and a gray arc on a gray capsule
                // reads as decoration instead of progress.
                tint: HeaderLogoColor.color(for: headerLogoColorHex),
                trackTint: palette.textTertiary
            )
            .frame(width: 13, height: 13)
        }
    }

    // MARK: - Expanded checklist

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(state.todos.enumerated()), id: \.element.id) { index, todo in
                PlanRowView(
                    index: index + 1,
                    todo: todo,
                    palette: palette,
                    reduceMotion: reduceMotion
                )
                .transition(ChatMotion.cardContentTransition(reduceMotion: reduceMotion))
                .animation(
                    ChatMotion.cardContent(
                        reduceMotion: reduceMotion,
                        delay: ChatMotion.cardContentLeadIn
                            + ChatMotion.cardRowDelay(index: staggerIndex(for: index), reduceMotion: reduceMotion)
                    ),
                    value: isExpanded
                )
            }
        }
    }

    // MARK: - Derived

    /// Upper bound so a long step can't stretch the card back to full width on
    /// a large phone. Past this the row wraps instead.
    ///
    /// `fixedSize` alone was not enough: it sizes to the widest row's *ideal*
    /// width, and a five-word step is already wider than this, so the card kept
    /// filling the screen. Capping the row label is what actually makes the
    /// card narrow — the cap has to bite on the text, not just the container.
    static let maximumWidth: CGFloat = 268

    private var beamStyle: BeamStyle {
        // Follows the accent hue rather than the user's global beam style, so
        // the plan's edge matches the orange running mark on the tool rows —
        // both are "this is live" in the same color. `.off` still wins, because
        // that setting means the user wants no traveling edges anywhere.
        //
        // Note the tool indicator's orange is the *accent* (`HeaderLogoColor`,
        // default #FFD700), not the `ember` preset, so `.accent` is what
        // actually matches it.
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

    /// Stagger order, measured from the pill outward.
    ///
    /// This card is anchored at its *bottom* (the pill sits above the composer)
    /// and grows upward, so it uncovers its last row first. Staggering in
    /// natural top-down order therefore fights the reveal: the rows the user
    /// can already see are the ones still waiting to fade in. Counting from the
    /// bottom row makes the fade follow the opening edge.
    private func staggerIndex(for index: Int) -> Int {
        max(0, state.todos.count - 1 - index)
    }

    private var completionFraction: Double {
        guard !state.todos.isEmpty else { return 0 }
        let resolved = state.todos.filter { $0.status.isResolved }.count
        return Double(resolved) / Double(state.todos.count)
    }

    private var progressLabel: String {
        if state.isFinished {
            return "\(state.todos.count) of \(state.todos.count)"
        }
        return "\(state.currentStep) of \(state.todos.count)"
    }

    private var accessibilityLabel: String {
        let done = state.todos.filter { $0.status == .completed }.count
        return "Plan, \(done) of \(state.todos.count) steps complete."
    }

    private var palette: ChatPalette {
        ChatPalette(
            colorScheme: colorScheme,
            backgroundStyle: ChatBackgroundStyle.storedValue(backgroundStyleRawValue),
            temperature: ChatPaletteTemperature.storedValue(paletteTemperatureRawValue)
        )
    }
}

// MARK: - Row

/// One numbered plan step.
private struct PlanRowView: View {
    let index: Int
    let todo: TodoItem
    let palette: ChatPalette
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            PlanStatusGlyph(status: todo.status, reduceMotion: reduceMotion, palette: palette)
                .frame(width: 15, height: 15)

            Text("\(index).")
                .font(AppFont.footnote().monospacedDigit())
                .foregroundStyle(palette.textTertiary)

            PlanRowLabel(
                text: todo.content,
                isStruck: todo.status.isResolved,
                color: todo.status.isResolved ? palette.textTertiary : palette.textPrimary,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: PlanTimelineView.maximumWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

/// Checkbox / spinner / cross for a plan row.
///
/// Status changes are an SF Symbol swap, so `.contentTransition(.symbolEffect(.replace))`
/// carries the transition natively — no custom animation for the tick itself.
/// (`.symbolEffect(.replace, value:)` is not the right spelling here: `replace`
/// is a content transition between two symbols, not a discrete effect fired at
/// one.)
private struct PlanStatusGlyph: View {
    let status: TodoItem.Status
    let reduceMotion: Bool
    let palette: ChatPalette

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .animation(
                reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.28, extraBounce: 0.08),
                value: status
            )
            .modifier(PlanSpinModifier(isActive: status == .inProgress, reduceMotion: reduceMotion))
    }

    private var symbolName: String {
        switch status {
        case .pending: "circle"
        case .inProgress: "circle.dotted"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .pending: palette.textTertiary
        case .inProgress: palette.textPrimary.opacity(0.8)
        case .completed: Color.green.opacity(0.85)
        case .cancelled: Color.red.opacity(0.55)
        }
    }
}

/// Continuous rotation for the in-progress row.
///
/// Deliberately `.animation(_:value:)` on a plain rotation rather than a
/// `TimelineView`: timelines ignore low-frequency mode and keep ticking
/// off-screen, which is the pattern the tool rows had to move away from.
private struct PlanSpinModifier: ViewModifier {
    let isActive: Bool
    let reduceMotion: Bool
    @State private var spinning = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(
                spinning
                    ? .linear(duration: 2.4).repeatForever(autoreverses: false)
                    : .default,
                value: spinning
            )
            .onAppear { spinning = isActive && !reduceMotion }
            .onChange(of: isActive) { _, active in spinning = active && !reduceMotion }
    }
}

/// Row text whose strikethrough sweeps in from the leading edge.
///
/// SwiftUI's `.strikethrough` toggles instantly, which reads as a hard cut on a
/// row that just completed. Drawing the rule as an overlay lets it animate its
/// own width, so the line draws itself across the words.
private struct PlanRowLabel: View {
    let text: String
    let isStruck: Bool
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        Text(text)
            .font(AppFont.footnote())
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: isStruck ? proxy.size.width : 0, height: 1)
                        .offset(y: proxy.size.height / 2)
                        // Single-line rows get a true sweep. A wrapped row would
                        // need one rule per line, so the overlay stands down and
                        // the row relies on its dimmed foreground instead.
                        .opacity(proxy.size.height > 24 ? 0 : 1)
                        .animation(
                            reduceMotion ? .easeOut(duration: 0.10) : .easeOut(duration: 0.22),
                            value: isStruck
                        )
                }
                .allowsHitTesting(false)
            }
    }
}

/// Thin ring that fills as steps resolve — the collapsed pill's progress cue.
private struct PlanProgressRing: View {
    let fraction: Double
    let reduceMotion: Bool
    let tint: Color
    /// Unfilled track. Defaults to a faded `tint` when omitted.
    var trackTint: Color?

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder((trackTint ?? tint).opacity(0.3), lineWidth: 1.8)

            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(0.9)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.10) : .smooth(duration: 0.32, extraBounce: 0),
            value: fraction
        )
    }
}
