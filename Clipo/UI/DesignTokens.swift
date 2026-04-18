import SwiftUI

enum DesignTokens {
    // MARK: - Brand (default; user can override via Defaults[.accentColorHex])
    static let defaultAccentHex = "#FF6A3D"
    static let accent = Color(hex: defaultAccentHex) ?? .orange
    static let accentSoft = Color(hex: "#FFD4C4") ?? .orange.opacity(0.3)

    // MARK: - Layout
    static let panelRadius: CGFloat = 20
    static let cardRadius: CGFloat = 14
    /// Form controls (search field, text inputs). Halfway between chip/pill
    /// and card so inputs feel grouped with cards without competing with them.
    static let inputRadius: CGFloat = 10
    static let cardWidth: CGFloat = 240
    static let cardHeight: CGFloat = 220
    static let cardSpacing: CGFloat = 12

    static let panelHorizontalPadding: CGFloat = 20
    static let panelTopPadding: CGFloat = 14
    static let panelBottomPadding: CGFloat = 10

    // MARK: - Motion
    static let selectSpring = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let hoverAnim = Animation.easeOut(duration: 0.18)

    // MARK: - Typography
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Text colors
    //
    // `Color.primary` is black in light mode and white in dark mode, so
    // overlaying it at a given opacity gives the same perceived contrast
    // against either background without branching.
    struct TextColor {
        static let primary   = Color.primary.opacity(0.88)
        static let secondary = Color.primary.opacity(0.62)
        static let tertiary  = Color.primary.opacity(0.40)
        static let faint     = Color.primary.opacity(0.22)
    }

    // MARK: - Surfaces
    //
    // Card fills use explicit light/dark stops so the translucent glass look
    // survives both appearances. Borders/chips/dividers lean on primary so
    // they auto-invert.
    struct Surface {
        static let cardFill = LinearGradient(
            colors: [
                Color(light: .white.opacity(0.88), dark: Color(white: 0.18).opacity(0.85)),
                Color(light: .white.opacity(0.72), dark: Color(white: 0.12).opacity(0.80))
            ],
            startPoint: .top, endPoint: .bottom
        )
        static let cardFillHover = LinearGradient(
            colors: [
                Color(light: .white.opacity(0.95), dark: Color(white: 0.22).opacity(0.90)),
                Color(light: .white.opacity(0.82), dark: Color(white: 0.16).opacity(0.85))
            ],
            startPoint: .top, endPoint: .bottom
        )
        static let cardBorder         = Color.primary.opacity(0.07)
        static let cardBorderHover    = Color.primary.opacity(0.16)
        static let cardBorderSelected = DesignTokens.accent
        static let chipFill           = Color.primary.opacity(0.06)
        static let chipBorder         = Color.primary.opacity(0.10)
        static let divider            = Color.primary.opacity(0.08)
        /// Full-panel wash tint that sits on top of the popover material.
        /// Lightens the chrome in light mode; darkens slightly in dark mode.
        static let panelWash = Color(
            light: Color.white.opacity(0.35),
            dark: Color(white: 0.10).opacity(0.30)
        )
    }
}
