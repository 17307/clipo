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
    static func attributed(_ source: String, query: String, accent: Color) -> AttributedString {
        var attr = AttributedString(source)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return attr }

        var cursor = attr.startIndex
        while cursor < attr.endIndex,
              let range = attr[cursor..<attr.endIndex].range(of: q, options: .caseInsensitive) {
            attr[range].backgroundColor = accent.opacity(0.35)
            attr[range].foregroundColor = .primary
            cursor = range.upperBound
        }
        return attr
    }
}
