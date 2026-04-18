import SwiftUI

/// Builds an `AttributedString` from a source string where every
/// case-insensitive occurrence of `query` is wrapped with an accent
/// background. Used to highlight the matched portion of card bodies + the
/// preview text when the user is actively searching.
///
/// Highlight uses substring matching across all search modes (exact /
/// contains / fuzzy). Fuzzy scattered-char highlights look visually
/// messy; substring matches are still right 95% of the time since most
/// fuzzy matches contain the literal query as a contiguous chunk.
enum SearchHighlight {
    static func attributed(
        _ source: String,
        query: String,
        accent: Color,
        colorScheme: ColorScheme = .light
    ) -> AttributedString {
        var attr = AttributedString(source)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return attr }

        // 0.35 is nearly invisible on dark card surfaces; push to 0.55 in
        // dark mode so the highlight actually reads. Light mode at 0.40 is
        // a visible-but-not-shouting tint against the translucent card.
        let opacity: Double = colorScheme == .dark ? 0.55 : 0.40

        var cursor = attr.startIndex
        while cursor < attr.endIndex,
              let range = attr[cursor..<attr.endIndex].range(of: q, options: .caseInsensitive) {
            attr[range].backgroundColor = accent.opacity(opacity)
            attr[range].foregroundColor = .primary
            cursor = range.upperBound
        }
        return attr
    }
}
