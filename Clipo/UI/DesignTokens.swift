import SwiftUI

enum DesignTokens {
    // MARK: - Brand (default; user can override via Defaults[.accentColorHex])
    static let defaultAccentHex = "#FF6A3D"
    static let accent = Color(hex: defaultAccentHex) ?? .orange
    static let accentSoft = Color(hex: "#FFD4C4") ?? .orange.opacity(0.3)

    // MARK: - Layout
    static let panelRadius: CGFloat = 20
    static let cardRadius: CGFloat = 14
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

    // MARK: - Text colors (for light translucent bg)
    struct TextColor {
        static let primary   = Color.black.opacity(0.88)
        static let secondary = Color.black.opacity(0.62)
        static let tertiary  = Color.black.opacity(0.40)
        static let faint     = Color.black.opacity(0.22)
    }

    // MARK: - Surfaces (light translucent)
    struct Surface {
        static let cardFill = LinearGradient(
            colors: [Color.white.opacity(0.88), Color.white.opacity(0.72)],
            startPoint: .top, endPoint: .bottom
        )
        static let cardFillHover = LinearGradient(
            colors: [Color.white.opacity(0.95), Color.white.opacity(0.82)],
            startPoint: .top, endPoint: .bottom
        )
        static let cardBorder         = Color.black.opacity(0.07)
        static let cardBorderHover    = Color.black.opacity(0.12)
        static let cardBorderSelected = DesignTokens.accent
        static let chipFill           = Color.black.opacity(0.05)
        static let chipBorder         = Color.black.opacity(0.08)
        static let divider            = Color.black.opacity(0.06)
    }
}
