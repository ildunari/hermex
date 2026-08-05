import SwiftUI

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
    case timesSerif

    static let storageKey = "chatTranscript.responseFontStyle"
    static let defaultValue = ResponseFontStyle.system

    var id: String { rawValue }

    var usesTimesSerif: Bool { self == .timesSerif }

    static func storedValue(_ rawValue: String?) -> ResponseFontStyle {
        rawValue.flatMap(ResponseFontStyle.init(rawValue:)) ?? defaultValue
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

    init(colorScheme: ColorScheme, backgroundStyle: ChatBackgroundStyle) {
        if colorScheme == .dark {
            chatBackground = Self.color(backgroundStyle == .black ? "#000000" : "#232220")
            surface = Self.color("#2E2C29")
            surfaceInset = Self.color("#383633")
            codeSlab = Self.color(backgroundStyle == .black ? "#161514" : "#1E1D1B")
            userBubble = Self.color("#33312E")
            textPrimary = Self.color("#F5F4F0")
            textSecondary = textPrimary.opacity(0.62)
            textTertiary = textPrimary.opacity(0.38)
            tableRule = textPrimary.opacity(0.14)
            inlineCodeFill = Color.white.opacity(0.09)
        } else {
            chatBackground = Self.color("#FAF9F7")
            surface = Self.color("#F1EFEA")
            surfaceInset = Self.color("#E9E6E0")
            codeSlab = Self.color("#F4F2ED")
            userBubble = Self.color("#EDEAE4")
            textPrimary = Self.color("#1B1A18")
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
