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
    /// Whether the session still has work in flight. Gates the beam.
    ///
    /// Every other beam in the app is activity-gated, but this is the one
    /// surface designed to *stay* open, so without a liveness input an expanded
    /// plan on an idle session drives a 30fps timeline and a per-frame
    /// rasterization forever. That is a battery cost with nothing to report.
    var isLive: Bool = false

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
            surfaceShape
                .fill(palette.surface.opacity(0.5))
                .overlay(surfaceShape.strokeBorder(palette.tableRule, lineWidth: 1))
        )
        // Glass sits over the tinted fill, not instead of it: the fill keeps the
        // palette's warmth, glass supplies the blur and specular edge. Matches
        // how `ChatActiveRunStatusView` layers the same two.
        .adaptiveGlass(
            .regular,
            isInteractive: false,
            fallbackMaterial: .regularMaterial,
            in: surfaceShape
        )
        .clipShape(surfaceShape)
        // Lifts the whole surface off the transcript so it floats above the
        // composer rather than being printed onto the canvas.
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12),
            radius: 8,
            y: 3
        )
        // The beam marks the card as live while it is open — the same signal the
        // thinking and tool blocks use, so the plan reads as one of that family.
        .borderBeam(
            style: beamStyle,
            shape: surfaceShape,
            active: chromeExpanded && isPlanRunning && beamStyle.isVisible
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
                    .contentTransition(
                        reduceMotion ? .identity : .numericText(value: Double(state.currentStep))
                    )
                    .lineLimit(1)
            }
            // Roomier than a status chip: the pill is the resting state of this
            // surface, so it reads as a control rather than a label. No chevron
            // — the whole pill is the hit target, and the affordance is the
            // floating shape itself.
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            // No surface of its own. The outer view owns the one background,
            // border, glass, and shadow for both states; the header only
            // supplies its hit target. Giving the header its own glass meant a
            // second `glassEffect` capsule stayed rendered inside the expanded
            // card — `glassEffect` paints its own surface and specular edge, so
            // fading the *fill and stroke* to zero could not hide it. That was
            // the double outline.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isExpanded ? "Double tap to collapse the plan." : "Double tap to expand the plan.")
    }

    @ViewBuilder
    private var progressGlyph: some View {
        // A plan whose steps were all *cancelled* is not a success. Only the
        // genuinely-completed case earns the green check.
        if state.isFinished, !state.hasCancelledWork {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.green.opacity(0.85))
        } else if state.isFinished {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.55))
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
            // Index-qualified identity: `TodoItem.id` falls back to its content
            // when the server omits an id, so two id-less rows with the same
            // text would collide and recycle onto each other mid-animation.
            ForEach(Array(state.todos.enumerated()), id: \.offset) { index, todo in
                PlanRowView(
                    index: index + 1,
                    todo: todo,
                    palette: palette,
                    reduceMotion: reduceMotion,
                    // A row stays `in_progress` forever if the stream dies
                    // before a final snapshot, so the spin follows session
                    // liveness rather than the row's status alone.
                    isLive: isLive
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

    /// The single surface shape, morphing between the collapsed pill and the
    /// expanded card.
    ///
    /// One `RoundedRectangle` whose radius animates rather than a
    /// `Capsule`/`RoundedRectangle` swap: swapping the type changes view
    /// identity, so SwiftUI replaces the surface instead of animating it — the
    /// same trap that produced the ghosted double-capsule on the activity
    /// blocks. A large radius on a short pill is visually identical to a
    /// capsule, so nothing is lost by expressing both as one shape.
    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: chromeExpanded ? ActivityBlockChrome.cornerRadius : Self.collapsedRadius,
            style: .continuous
        )
    }

    /// Half the collapsed pill's height, which is what makes it read as a
    /// capsule. Height is 9pt padding twice plus a footnote line.
    private static let collapsedRadius: CGFloat = 19

    /// Upper bound so a long step can't stretch the card back to full width on
    /// a large phone. Past this the row wraps instead.
    ///
    /// `fixedSize` alone was not enough: it sizes to the widest row's *ideal*
    /// width, and a five-word step is already wider than this, so the card kept
    /// filling the screen. Capping the row label is what actually makes the
    /// card narrow — the cap has to bite on the text, not just the container.
    static let maximumWidth: CGFloat = 268

    /// The plan is doing work: a row is in progress and the session still has
    /// a stream attached. A finished plan, or one left open on an idle session,
    /// has nothing to report and must not keep the beam running.
    private var isPlanRunning: Bool {
        isLive && state.todos.contains { $0.status == .inProgress }
    }

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
    /// Session still streaming; see `PlanTimelineView.isLive`.
    var isLive: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            PlanStatusGlyph(
                status: todo.status,
                reduceMotion: reduceMotion,
                palette: palette,
                isLive: isLive
            )
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
        // Status is otherwise conveyed only by symbol shape and color, neither
        // of which VoiceOver reads.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index), \(statusDescription): \(todo.content)")
    }

    private var statusDescription: String {
        switch todo.status {
        case .pending: String(localized: "not started")
        case .inProgress: String(localized: "in progress")
        case .completed: String(localized: "completed")
        case .cancelled: String(localized: "cancelled")
        }
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
    var isLive: Bool = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .animation(
                reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.28, extraBounce: 0.08),
                value: status
            )
            .modifier(PlanSpinModifier(isActive: isLive && status == .inProgress, reduceMotion: reduceMotion))
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
