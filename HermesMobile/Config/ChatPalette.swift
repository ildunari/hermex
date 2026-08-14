import SwiftUI

/// The single appearance axis for the chat canvas and every app surface.
///
/// Warm is the tuned paper/ember stack: ivory in light mode, warm charcoal in
/// dark. Standard is the clinical high-contrast counterpart: pure white in
/// light mode, pure black in dark, with Apple's neutral grays for the raised
/// surfaces that sit on top.
///
/// This replaces the former `ChatBackgroundStyle` control, which offered a
/// separate dark-canvas depth choice. Its two options were also named
/// Warm/Black, which read as a duplicate of this setting and could contradict
/// it (Standard palette + "Warm" background produced a neutral gray canvas).
/// Pure black now lives where it belongs: as the dark half of Standard.
enum ChatPaletteTemperature: String, CaseIterable, Identifiable {
    case warm
    case standard

    static let storageKey = "appearance.chatPaletteTemperature"
    static let defaultValue = ChatPaletteTemperature.warm

    var id: String { rawValue }

    var usesWarmSurfaces: Bool { self == .warm }

    var title: String {
        switch self {
        case .warm:
            String(localized: "Warm")
        case .standard:
            String(localized: "Standard")
        }
    }

    static func storedValue(_ rawValue: String?) -> ChatPaletteTemperature {
        rawValue.flatMap(ChatPaletteTemperature.init(rawValue:)) ?? defaultValue
    }
}

/// Interactive-state colors that follow the Warm/Standard surface preference.
/// Standard remains neutral instead of falling back to the system blue accent.
struct ChatPaletteAccent {
    let selection: Color
    let selectionForeground: Color

    static func resolved(temperature: ChatPaletteTemperature, colorScheme: ColorScheme) -> Self {
        if temperature.usesWarmSurfaces {
            return Self(
                selection: Color(hexRGB: colorScheme == .dark ? "#D4A875" : "#9A6A43") ?? .brown,
                selectionForeground: colorScheme == .dark ? .black : .white
            )
        }

        return Self(
            selection: Color(hexRGB: colorScheme == .dark ? "#C7C7CC" : "#4A4A4F") ?? .secondary,
            selectionForeground: colorScheme == .dark ? .black : .white
        )
    }
}

enum ResponseFontStyle: String, CaseIterable, Identifiable {
    case system
    case serif

    static let storageKey = "chatTranscript.responseFontStyle"
    static let defaultValue = ResponseFontStyle.system

    var id: String { rawValue }

    var usesSerif: Bool { self == .serif }

    static func storedValue(_ rawValue: String?) -> ResponseFontStyle {
        // Preserve the short-lived pre-release value from the first theme
        // checkpoint while moving the UI to the more refined New York face.
        if rawValue == "timesSerif" {
            return .serif
        }
        return rawValue.flatMap(ResponseFontStyle.init(rawValue:)) ?? defaultValue
    }
}

/// Resolved beam appearance handed to the border-beam renderer. `colors` are
/// the visible gradient stops of the traveling segment (the renderer fades the
/// segment's head/tail itself), `strength` scales overall opacity, and
/// `cycleDuration` is one full trip around the card in seconds.
struct ResolvedBeam {
    let colors: [Color]
    let strength: Double
    let cycleDuration: Double

    static let none = ResolvedBeam(colors: [], strength: 0, cycleDuration: 0)

    var isVisible: Bool { strength > 0 && !colors.isEmpty }
}

/// User-selectable style for the traveling glow around live thinking and tool
/// activity. Hues are tuned to sit on both the warm (#232220 / #FAF9F7) and
/// standard (#1C1C1E / #FFFFFF) canvases: brightness carries the effect in
/// dark mode, saturation carries it in light mode, and no stop is pure neon.
enum ActivityBeamStyle: String, CaseIterable, Identifiable {
    case off
    case ink
    case accent
    case ember
    case aurora

    static let storageKey = "activityBeamStyle"
    static let defaultValue = ActivityBeamStyle.ink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            String(localized: "Off")
        case .ink:
            String(localized: "Ink")
        case .accent:
            String(localized: "Accent")
        case .ember:
            String(localized: "Ember")
        case .aurora:
            String(localized: "Aurora")
        }
    }

    static func storedValue(_ rawValue: String?) -> ActivityBeamStyle {
        rawValue.flatMap(ActivityBeamStyle.init(rawValue:)) ?? defaultValue
    }

    /// Resolves the beam gradient for the current palette and scheme.
    ///
    /// `accent` is passed by the caller (typically
    /// `HeaderLogoColor.color(for:)` read via `@AppStorage`) rather than read
    /// from storage here, so this type stays a pure appearance mapping and the
    /// view owning the beam re-renders when the header color changes.
    func resolved(
        palette: ChatPalette,
        colorScheme: ColorScheme,
        accent: Color
    ) -> ResolvedBeam {
        let isDark = colorScheme == .dark
        switch self {
        case .off:
            return .none
        case .ink:
            // Monochrome sweep derived from the palette's own text color so it
            // matches all four palette/scheme combos without extra tuning:
            // white-leaning and bright in dark mode, deep and restrained in
            // light mode.
            let peak = palette.textPrimary.opacity(isDark ? 0.9 : 0.35)
            let shoulder = palette.textPrimary.opacity(isDark ? 0.45 : 0.18)
            return ResolvedBeam(
                colors: [shoulder, peak, shoulder],
                strength: 0.55,
                cycleDuration: 2.6
            )
        case .accent:
            // Single-hue sweep in the user's chosen header accent.
            let peak = accent.opacity(isDark ? 0.95 : 0.8)
            let shoulder = accent.opacity(isDark ? 0.4 : 0.3)
            return ResolvedBeam(
                colors: [shoulder, peak, shoulder],
                strength: 0.7,
                cycleDuration: 2.6
            )
        case .ember:
            // Dramatic warm gradient. Dark mode leans on brightness; light
            // mode swaps to deeper, slightly desaturated embers so it doesn't
            // scream on white/ivory canvases.
            let stops: [Color] = isDark
                ? [
                    Self.color("#E8853D"),  // orange
                    Self.color("#F2B441"),  // amber
                    Self.color("#D96A55")   // soft red
                ]
                : [
                    Self.color("#C2691F").opacity(0.75),
                    Self.color("#C98F1B").opacity(0.75),
                    Self.color("#B14A38").opacity(0.75)
                ]
            return ResolvedBeam(colors: stops, strength: 0.8, cycleDuration: 2.2)
        case .aurora:
            // Dramatic cool gradient with extra stops for a hue-drifting feel.
            let stops: [Color] = isDark
                ? [
                    Self.color("#3FBFAE"),  // teal
                    Self.color("#5B8CE8"),  // blue
                    Self.color("#8E6BD9"),  // violet
                    Self.color("#4A9ED9")   // back toward blue
                ]
                : [
                    Self.color("#1F8C7D").opacity(0.72),
                    Self.color("#3B63C4").opacity(0.72),
                    Self.color("#6E4BB8").opacity(0.72),
                    Self.color("#2F7CB3").opacity(0.72)
                ]
            return ResolvedBeam(colors: stops, strength: 0.8, cycleDuration: 3.0)
        }
    }

    private static func color(_ hex: String) -> Color {
        Color(hexRGB: hex) ?? .primary
    }
}

/// Semantic transcript colors shared by markdown, bubbles, and the chat canvas.
/// Dark surfaces stay deliberately warm; light mode always uses warm ivory.
struct ChatPalette {
    let chatBackground: Color
    let surface: Color
    let surfaceInset: Color
    let codeSlab: Color
    let userBubble: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let tableRule: Color
    let inlineCodeFill: Color
    /// Foreground for inline code spans; typographic emphasis replaces the old
    /// gray slab background (which produced hard rectangles on wrapped spans).
    let inlineCodeText: Color
    /// Faint background wash behind blockquote content.
    let quoteWash: Color

    init(
        colorScheme: ColorScheme,
        temperature: ChatPaletteTemperature = .warm
    ) {
        let isWarm = temperature.usesWarmSurfaces
        if colorScheme == .dark {
            // Standard goes to true black rather than Apple's #1C1C1E: it is
            // the high-contrast/OLED choice, and the raised surfaces below
            // stay neutral gray so chrome still reads as system chrome
            // floating on black instead of a flat void.
            chatBackground = Self.color(isWarm ? "#232220" : "#000000")
            surface = Self.color(isWarm ? "#2E2C29" : "#2C2C2E")
            surfaceInset = Self.color(isWarm ? "#383633" : "#3A3A3C")
            codeSlab = Self.color(isWarm ? "#1E1D1B" : "#141416")
            userBubble = Self.color(isWarm ? "#33312E" : "#313135")
            textPrimary = Self.color(isWarm ? "#F5F4F0" : "#F2F2F7")
            textSecondary = textPrimary.opacity(0.62)
            textTertiary = textPrimary.opacity(0.38)
            tableRule = textPrimary.opacity(0.14)
            inlineCodeFill = Color.white.opacity(0.09)
            inlineCodeText = (isWarm ? Self.color("#F6F1E7") : textPrimary).opacity(0.92)
            quoteWash = Color.white.opacity(0.04)
        } else {
            // Light-mode warm ramp is tuned to stay perceptible on-device.
            // The previous canvas (#FAF9F7) sat ~2% off pure white, which is
            // below the swing True Tone/Night Shift apply to the display, so
            // the warm preference read as plain white under most lighting.
            // These values keep the same relative step spacing (canvas is
            // still the lightest token, then surface/codeSlab, then bubble,
            // then inset) while carrying a stronger ivory bias.
            chatBackground = Self.color(isWarm ? "#F7F4EE" : "#FFFFFF")
            surface = Self.color(isWarm ? "#EFEBE2" : "#F2F2F7")
            surfaceInset = Self.color(isWarm ? "#E6E1D6" : "#E5E5EA")
            codeSlab = Self.color(isWarm ? "#F2EEE5" : "#F2F2F7")
            userBubble = Self.color(isWarm ? "#EAE5DA" : "#E9E9EE")
            textPrimary = Self.color(isWarm ? "#1B1A18" : "#1C1C1E")
            textSecondary = textPrimary.opacity(0.55)
            textTertiary = textPrimary.opacity(0.35)
            tableRule = textPrimary.opacity(0.14)
            inlineCodeFill = Color.black.opacity(0.07)
            inlineCodeText = textPrimary.opacity(0.85)
            quoteWash = Color.black.opacity(0.03)
        }
    }

    private static func color(_ hex: String) -> Color {
        Color(hexRGB: hex) ?? .primary
    }
}

extension ChatPaletteTemperature {
    /// Legacy key for the removed `ChatBackgroundStyle` control (Warm/Black
    /// dark-canvas depth), retired when pure black became the dark half of
    /// Standard.
    static let legacyBackgroundStyleKey = "appearance.chatBackgroundStyle"

    /// Retires the legacy dark-canvas preference.
    ///
    /// Intent is preserved where it can be: a stored `black` means the user
    /// wanted a pure-black dark canvas, which is now exactly what Standard
    /// gives them, so we move them onto Standard. That is the honest read of
    /// the old choice even though it also switches their light mode from ivory
    /// to pure white — the two are now one palette by design. Anyone left on
    /// the old `warm` value already matches Warm's charcoal, so only the stale
    /// key is cleared.
    static func migrateLegacyBackgroundStyle(defaults: UserDefaults = .standard) {
        guard let legacy = defaults.string(forKey: legacyBackgroundStyleKey) else { return }
        if legacy == "black", defaults.string(forKey: storageKey) == nil {
            defaults.set(ChatPaletteTemperature.standard.rawValue, forKey: storageKey)
        }
        defaults.removeObject(forKey: legacyBackgroundStyleKey)
    }
}

extension ChatPalette {
    /// Resolves the palette from the stored preference, for chrome outside the
    /// transcript (navigation, session list) that should inherit the canvas
    /// appearance without each screen re-deriving it.
    ///
    /// - Important: This variant reads `UserDefaults` directly, so SwiftUI does
    ///   not register a dependency on the preference. Calling it from inside a
    ///   `body` means the view will NOT re-render when the palette changes; it
    ///   only picks up the new value on an unrelated rebuild. Use
    ///   ``appChrome(colorScheme:temperatureRawValue:)``
    ///   from view bodies and keep this one for non-view call sites.
    static func appChrome(colorScheme: ColorScheme) -> ChatPalette {
        let defaults = UserDefaults.standard
        return ChatPalette(
            colorScheme: colorScheme,
            temperature: ChatPaletteTemperature.storedValue(
                defaults.string(forKey: ChatPaletteTemperature.storageKey)
            )
        )
    }

    /// Reactive variant of ``appChrome(colorScheme:)``.
    ///
    /// Callers pass the raw value sourced from `@AppStorage`, which gives
    /// SwiftUI a real dependency edge on the stored preference. That makes
    /// chrome re-render immediately when the palette changes, instead of
    /// waiting for an incidental view rebuild.
    static func appChrome(
        colorScheme: ColorScheme,
        temperatureRawValue: String?
    ) -> ChatPalette {
        ChatPalette(
            colorScheme: colorScheme,
            temperature: ChatPaletteTemperature.storedValue(temperatureRawValue)
        )
    }
}

/// Semantic role of an app surface, so screens outside the transcript can adopt
/// the palette without each one re-deriving which token to use.
enum AppSurfaceRole {
    /// Full-screen canvas behind a screen's content.
    case canvas
    /// Cards, rows, and raised containers sitting on the canvas.
    case surface
    /// Nested panels, chips, and controls inside a card.
    case inset
}

private struct AppSurfaceBackgroundModifier<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    // Read the preference through @AppStorage rather than calling the
    // UserDefaults-backed appChrome(colorScheme:) directly. This gives SwiftUI
    // a dependency edge on the key, so every screen using
    // `appSurfaceBackground` repaints the moment the palette changes instead of
    // waiting for an unrelated rebuild.
    @AppStorage(ChatPaletteTemperature.storageKey) private var temperatureRawValue: String?

    let role: AppSurfaceRole
    let opacity: Double
    let shape: S?

    func body(content: Content) -> some View {
        let palette = ChatPalette.appChrome(
            colorScheme: colorScheme,
            temperatureRawValue: temperatureRawValue
        )
        let color: Color = {
            switch role {
            case .canvas: palette.chatBackground
            case .surface: palette.surface
            case .inset: palette.surfaceInset
            }
        }().opacity(opacity)

        if let shape {
            content.background(color, in: shape)
        } else {
            content.background(color)
        }
    }
}

extension View {
    /// Applies a palette-driven background so every screen inherits the chosen
    /// chat palette instead of hardcoding system grays.
    func appSurfaceBackground(_ role: AppSurfaceRole, opacity: Double = 1) -> some View {
        modifier(AppSurfaceBackgroundModifier<Rectangle>(role: role, opacity: opacity, shape: nil))
    }

    func appSurfaceBackground(
        _ role: AppSurfaceRole,
        opacity: Double = 1,
        in shape: some Shape
    ) -> some View {
        modifier(AppSurfaceBackgroundModifier(role: role, opacity: opacity, shape: shape))
    }
}
