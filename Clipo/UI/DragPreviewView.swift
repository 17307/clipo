import SwiftUI

/// Minimal view used as the SwiftUI `.onDrag` preview (the image that
/// follows the cursor during a drag session).
///
/// The default `.onDrag` preview is a full snapshot of the source view
/// — in our case a ~240×220 card with drop shadow, gradient fill,
/// stroke border, accent tint, and stack-position chip. The
/// compositor then drags that heavyweight image around every frame
/// while the main panel is still visible underneath, which reads as
/// a stutter on non-M-series hardware and under GPU load.
///
/// This replacement is just a small rounded card with a kind-indicator
/// glyph and a short content snippet. No shadow, no gradient, no
/// nested overlays — cheap to composite even at full retina
/// resolution.
struct DragPreviewView: View {
    let item: ClipItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var glyph: String {
        switch item.primaryKind {
        case .text:  return "doc.text"
        case .url:   return "link"
        case .image: return "photo"
        case .color: return "paintpalette.fill"
        case .file:  return "doc.fill"
        }
    }

    private var label: String {
        if !item.fileURLs.isEmpty {
            if item.fileURLs.count == 1 {
                return item.fileURLs[0].lastPathComponent
            }
            return "\(item.fileURLs.count) files"
        }
        let snippet = item.previewableText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if snippet.isEmpty {
            return item.title.isEmpty ? "Clip" : item.title
        }
        return String(snippet.prefix(60))
    }
}
