import SwiftUI

/// Hue temperature of the chat canvas and its surfaces. Independent of the
/// dark-canvas depth choice in `ChatBackgroundStyle`: warm uses the tuned
/// warm-gray stack, standard falls back to neutral system grays.
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

enum ChatBackgroundStyle: String, CaseIterable, Identifiable {
    case warm
    case black

    static let storageKey = "appearance.chatBackgroundStyle"
    static let defaultValue = ChatBackgroundStyle.warm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm:
            String(localized: "Warm")
        case .black:
            String(localized: "Black")
        }
    }

    static func storedValue(_ rawValue: String?) -> ChatBackgroundStyle {
        rawValue.flatMap(ChatBackgroundStyle.init(rawValue:)) ?? defaultValue
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

    init(
        colorScheme: ColorScheme,
        backgroundStyle: ChatBackgroundStyle,
        temperature: ChatPaletteTemperature = .warm
    ) {
        let isWarm = temperature.usesWarmSurfaces
        if colorScheme == .dark {
            chatBackground = Self.color(
                backgroundStyle == .black ? "#000000" : (isWarm ? "#232220" : "#1C1C1E")
            )
            surface = Self.color(isWarm ? "#2E2C29" : "#2C2C2E")
            surfaceInset = Self.color(isWarm ? "#383633" : "#3A3A3C")
            codeSlab = Self.color(
                backgroundStyle == .black
                    ? (isWarm ? "#161514" : "#141416")
                    : (isWarm ? "#1E1D1B" : "#1A1A1C")
            )
            userBubble = Self.color(isWarm ? "#33312E" : "#313135")
            textPrimary = Self.color(isWarm ? "#F5F4F0" : "#F2F2F7")
            textSecondary = textPrimary.opacity(0.62)
            textTertiary = textPrimary.opacity(0.38)
            tableRule = textPrimary.opacity(0.14)
            inlineCodeFill = Color.white.opacity(0.09)
        } else {
            chatBackground = Self.color(isWarm ? "#FAF9F7" : "#FFFFFF")
            surface = Self.color(isWarm ? "#F1EFEA" : "#F2F2F7")
            surfaceInset = Self.color(isWarm ? "#E9E6E0" : "#E5E5EA")
            codeSlab = Self.color(isWarm ? "#F4F2ED" : "#F2F2F7")
            userBubble = Self.color(isWarm ? "#EDEAE4" : "#E9E9EE")
            textPrimary = Self.color(isWarm ? "#1B1A18" : "#1C1C1E")
            textSecondary = textPrimary.opacity(0.55)
            textTertiary = textPrimary.opacity(0.35)
            tableRule = textPrimary.opacity(0.14)
            inlineCodeFill = Color.black.opacity(0.07)
        }
    }

    private static func color(_ hex: String) -> Color {
        Color(hexRGB: hex) ?? .primary
    }
}

extension ChatPalette {
    /// Resolves the palette from the stored background preference, for chrome
    /// outside the transcript (navigation, session list) that should inherit the
    /// canvas warmth without owning the dark-canvas choice itself.
    static func appChrome(colorScheme: ColorScheme) -> ChatPalette {
        let defaults = UserDefaults.standard
        return ChatPalette(
            colorScheme: colorScheme,
            backgroundStyle: ChatBackgroundStyle.storedValue(
                defaults.string(forKey: ChatBackgroundStyle.storageKey)
            ),
            temperature: ChatPaletteTemperature.storedValue(
                defaults.string(forKey: ChatPaletteTemperature.storageKey)
            )
        )
    }
}
