import AppKit
import Defaults
import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    /// The digit shown in the ⌥1–⌥9 quick-paste badge, counted from
    /// the currently selected card (selected = 1, incrementing from
    /// there). nil hides the badge — used for cards before the
    /// selection or beyond the 9-card window. Computed by the
    /// carousel parent, for the same reason `multiPosition` is:
    /// observing `selectedID` here would cascade re-renders.
    let quickPasteBadge: Int?
    let isSelected: Bool
    /// 1-based position in the paste stack when this card is part of a
    /// multi-selection. Nil means the card is not currently multi-selected.
    /// Computed by the carousel parent so this view doesn't have to observe
    /// AppState directly (would cause cascading re-renders on isOptionDown).
    let multiPosition: Int?

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.accentColorHex) private var accentHex

    // Intentionally NOT subscribing to AppState here — `isOptionDown`'s
    // cascading observation used to re-render every visible card. Only the
    // nested `IndexBadge` view watches that flag now.

    private var accent: Color { Color(hex: accentHex) ?? DesignTokens.accent }
    private var isMultiSelected: Bool { multiPosition != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(item: item, quickPasteBadge: quickPasteBadge)
            Rectangle()
                .fill(DesignTokens.Surface.divider)
                .frame(height: 0.5)
            cardBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle()
                .fill(DesignTokens.Surface.divider)
                .frame(height: 0.5)
            CardFooter(item: item)
        }
        .frame(width: DesignTokens.cardWidth, height: DesignTokens.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .fill(isHovering ? DesignTokens.Surface.cardFillHover : DesignTokens.Surface.cardFill)
        )
        .overlay(
            // Accent tint overlay when part of a multi-selection — it reads
            // as a "marked for batch action" state distinct from the single-
            // focus highlight (which is carried by the shadow + scale).
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .fill(accent.opacity(isMultiSelected ? 0.14 : 0))
                .allowsHitTesting(false)
        )
        .overlay(
            // Constant 1pt border — the accent glow (shadow below) does the
            // work of signalling selection. Jumping to 1.5pt on select adds
            // a mechanical "pop wider" feel that Paste-style cards avoid.
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if let position = multiPosition {
                StackPositionChip(position: position, accent: accent)
                    .padding(6)
            }
        }
        .scaleEffect(scaleFactor)
        .shadow(
            // Unselected: a subtle drop so cards lift from the chrome.
            // Dark mode swaps to a brighter fill-based halo since a dark
            // shadow on a dark surface would disappear. Multi-select
            // suppresses the halo so a whole group doesn't glow.
            color: isSelected && !isMultiSelected
                ? accent.opacity(0.30)
                : Color(light: .black.opacity(0.10), dark: .black.opacity(0.45)),
            radius: isSelected && !isMultiSelected ? 14 : 5,
            x: 0, y: isSelected && !isMultiSelected ? 6 : 2
        )
        .animation(reduceMotion ? nil : DesignTokens.selectSpring, value: isSelected)
        .animation(reduceMotion ? nil : DesignTokens.selectSpring, value: isMultiSelected)
        .animation(reduceMotion ? nil : DesignTokens.hoverAnim, value: isHovering)
        .onHover { hovering in
            // Skip hover state updates while the user is holding a
            // mouse button — they're almost certainly mid-drag and
            // the cursor is sweeping across other cards. Each
            // isHovering toggle triggers a 0.18s scale/shadow
            // animation; letting them stack while a drag session is
            // alive adds compositor load that reads as drag-preview
            // stutter. Next unmodified hover after mouseUp corrects
            // the state if it was stale.
            guard NSEvent.pressedMouseButtons == 0 else { return }
            isHovering = hovering
        }
        .pointingHand()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Item \(index). Press Return to paste, Space to preview.")
        .accessibilityAddTraits(isSelected || isMultiSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Human-readable summary for VoiceOver. Composes kind + source + a
    /// truncated content preview. Kept under ~140 chars so the speech
    /// doesn't drag on when navigating card-by-card.
    private var accessibilityDescription: String {
        let kind: String = {
            switch item.primaryKind {
            case .text:  return "Text"
            case .url:   return "Link"
            case .image: return "Image"
            case .color: return "Color"
            case .file:  return "File"
            }
        }()
        let source = AppIconCache.appName(forBundleID: item.sourceAppBundleID)
        let time = SharedFormatters.relativeTime.localizedString(
            for: item.lastCopiedAt, relativeTo: .now
        )
        let preview = item.title.shortened(to: 120)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.isEmpty {
            return "\(kind) from \(source), \(time)"
        }
        return "\(kind) from \(source), \(time): \(preview)"
    }

    private var scaleFactor: CGFloat {
        // Suppress the single-select bounce while multi-selecting so the
        // group reads as a cohesive block rather than one card leaping out.
        if isSelected && !isMultiSelected { return 1.04 }
        if isHovering { return 1.015 }
        return 1.0
    }

    private var borderColor: Color {
        if isMultiSelected { return accent.opacity(0.7) }
        if isSelected { return accent.opacity(0.9) }
        if isHovering { return DesignTokens.Surface.cardBorderHover }
        return DesignTokens.Surface.cardBorder
    }

    @ViewBuilder
    private var cardBody: some View {
        switch item.primaryKind {
        case .text:  TextBody(item: item)
        case .url:   URLBody(item: item)
        case .image: ImageBody(item: item)
        case .color: ColorBody(item: item)
        case .file:  FileBody(item: item)
        }
    }
}

// MARK: - Header (source app + index)

private struct CardHeader: View {
    let item: ClipItem
    /// Digit to show in the ⌥N badge; nil hides it. Precomputed by
    /// the carousel so this view doesn't need to observe
    /// `AppState.selectedID`.
    let quickPasteBadge: Int?

    @Default(.showSourceIcon) private var showSourceIcon

    // Does NOT read AppState. `isOptionDown` changes are isolated to
    // `IndexBadge` so CardHeader itself doesn't re-render each time Option
    // is pressed.

    /// Icon resolved from `AppIconCache`. Initialised from the cache peek
    /// on first body eval (no main-thread LaunchServices), filled in by
    /// the `.task` modifier below when the cache is cold.
    @State private var resolvedIcon: NSImage?
    @State private var resolvedName: String?

    var body: some View {
        HStack(spacing: 7) {
            if showSourceIcon {
                sourceIcon
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(sourceName)
                    .font(DesignTokens.rounded(10.5, weight: .medium))
                    .foregroundStyle(DesignTokens.TextColor.secondary)
                    .lineLimit(1)
            } else {
                Text(relativeTime)
                    .font(DesignTokens.rounded(10.5, weight: .medium))
                    .foregroundStyle(DesignTokens.TextColor.secondary)
            }
            Spacer(minLength: 4)
            if let badge = quickPasteBadge, badge >= 1, badge <= 9 {
                IndexBadge(index: badge)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Async resolve only when we actually render the icon/name row.
        // `.task(id:)` reruns when the card is recycled onto a different
        // bundleID (LazyHStack reuse).
        .task(id: item.sourceAppBundleID) {
            if !showSourceIcon { return }
            let bundle = item.sourceAppBundleID
            // Fast path — already cached, no detached Task hop.
            if let img = AppIconCache.cachedIcon(forBundleID: bundle),
               let name = AppIconCache.cachedAppName(forBundleID: bundle) {
                resolvedIcon = img
                resolvedName = name
                return
            }
            // Slow path — hit LaunchServices off-main.
            let (img, name) = await Task.detached(priority: .userInitiated) {
                (AppIconCache.icon(forBundleID: bundle), AppIconCache.appName(forBundleID: bundle))
            }.value
            resolvedIcon = img
            resolvedName = name
        }
    }

    private var relativeTime: String {
        SharedFormatters.relativeTime.localizedString(for: item.lastCopiedAt, relativeTo: .now)
    }

    @ViewBuilder
    private var sourceIcon: some View {
        // Prefer the async-resolved icon; fall back to a direct cache peek
        // so a cache-warm bundle renders correctly on the very first body
        // eval, before `.task` has had a chance to run.
        let img = resolvedIcon ?? AppIconCache.cachedIcon(forBundleID: item.sourceAppBundleID)
        if let img {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(DesignTokens.TextColor.tertiary)
        }
    }

    private var sourceName: String {
        // Same pattern as `sourceIcon` — async-resolved first, cache peek
        // second, bundle id as a last-resort so we never show "Unknown".
        if let name = resolvedName { return name }
        if let cached = AppIconCache.cachedAppName(forBundleID: item.sourceAppBundleID) {
            return cached
        }
        return item.sourceAppBundleID ?? "Unknown"
    }

}

// MARK: - Stack position chip (shown when card is part of a multi-selection)

/// Small accent capsule showing the 1-based position in the paste queue.
/// Appears top-right of any multi-selected card; lets the user see at a
/// glance which item will be pasted first, second, third, etc.
private struct StackPositionChip: View {
    let position: Int
    let accent: Color

    var body: some View {
        Text("\(position)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 5)
            .background(
                Capsule()
                    .fill(accent)
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            )
            .accessibilityLabel("Stack position \(position)")
    }
}

// MARK: - Index badge (subscribes to AppState.isOptionDown in isolation)

private struct IndexBadge: View {
    let index: Int

    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.accentColorHex) private var accentHex

    private var accent: Color { Color(hex: accentHex) ?? DesignTokens.accent }

    var body: some View {
        Group {
            if state.isOptionDown {
                // Prominent state: accent capsule with ⌥ prefix.
                HStack(spacing: 1) {
                    Text("⌥")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                    Text("\(index)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(
                    Capsule()
                        .fill(accent.gradient)
                        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                )
            } else {
                // Default state: subtle numeric circle.
                Text("\(index)")
                    .font(DesignTokens.rounded(9, weight: .bold))
                    .foregroundStyle(DesignTokens.TextColor.secondary)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.primary.opacity(0.09)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: state.isOptionDown)
    }
}

// MARK: - Footer (time + stats + copy count)

private struct CardFooter: View {
    let item: ClipItem

    @Default(.accentColorHex) private var accentHex

    private var accent: Color { Color(hex: accentHex) ?? DesignTokens.accent }

    var body: some View {
        HStack(spacing: 6) {
            // Time label doubles as the tooltip affordance. Hovering it
            // for ~1s (SwiftUI's system tooltip delay) surfaces the
            // absolute capture time + source app — scoped to this tiny
            // corner instead of the whole card so the tooltip doesn't
            // keep flashing in and out as the cursor sweeps across cards.
            Text(relativeTime)
                .font(DesignTokens.rounded(10, weight: .medium))
                .foregroundStyle(DesignTokens.TextColor.tertiary)
                .help(detailedTooltip)
            Spacer(minLength: 4)
            // Images that finished OCR advertise it with a small chip so
            // users know "this screenshot is also searchable by its
            // contents" — otherwise the feature is invisible until
            // someone happens to search for the right word.
            if item.primaryKind == .image, let ocr = item.ocrText, !ocr.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 8, weight: .semibold))
                    Text("OCR")
                        .font(DesignTokens.rounded(9, weight: .bold))
                }
                .foregroundStyle(DesignTokens.TextColor.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .help("Recognised \(ocr.count) chars of text — searchable")
            }
            if let stat = statText {
                Text(stat)
                    .font(DesignTokens.mono(9.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.TextColor.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            if item.numberOfCopies > 1 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(item.numberOfCopies)")
                        .font(DesignTokens.rounded(9.5, weight: .bold))
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(accent.opacity(0.12)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var relativeTime: String {
        SharedFormatters.relativeTime.localizedString(for: item.lastCopiedAt, relativeTo: .now)
    }

    /// Shown on hover over the relative-time label after the ~1s system
    /// tooltip delay. Gives the user the exact capture time + source app
    /// without having to pop the preview. Deliberately anchored to the
    /// footer's time text (instead of the whole card) so a cursor just
    /// passing through the carousel doesn't fire the tooltip.
    private var detailedTooltip: String {
        let absolute = SharedFormatters.absoluteTime.string(from: item.lastCopiedAt)
        let relative = SharedFormatters.relativeTimeFull.localizedString(
            for: item.lastCopiedAt, relativeTo: .now
        )
        let source = AppIconCache.appName(forBundleID: item.sourceAppBundleID)
        return "\(absolute) · \(relative)\nFrom \(source)"
    }

    private var statText: String? {
        switch item.primaryKind {
        case .image:
            if let img = item.image {
                return "\(Int(img.size.width))×\(Int(img.size.height))"
            }
            return nil
        case .file:
            let n = item.fileURLs.count
            return n == 1 ? "1 file" : "\(n) files"
        case .text, .url, .color:
            if let t = item.text {
                return "\(t.count) chars"
            }
            return nil
        }
    }
}

// MARK: - Body variants

private struct TextBody: View {
    let item: ClipItem
    var body: some View {
        let raw = (item.text ?? item.title).trimmingCharacters(in: .whitespacesAndNewlines)
        Text(String(raw.prefix(600)))
            .font(DesignTokens.rounded(12, weight: .regular))
            .foregroundStyle(DesignTokens.TextColor.primary)
            .lineSpacing(3)
            .lineLimit(8)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

private struct URLBody: View {
    let item: ClipItem
    @Default(.accentColorHex) private var accentHex
    var body: some View {
        let url = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let components = URL(string: url)
        let accent = Color(hex: accentHex) ?? DesignTokens.accent
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(components?.host ?? "link")
                    .font(DesignTokens.rounded(11.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.TextColor.primary)
                    .lineLimit(1)
                Spacer()
            }
            Text(url)
                .font(DesignTokens.mono(11))
                .foregroundStyle(DesignTokens.TextColor.secondary)
                .lineLimit(5)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ImageBody: View {
    let item: ClipItem
    var body: some View {
        Group {
            if let img = item.image {
                // `.fit` scales the image down so the whole picture is visible,
                // letterboxed inside the body rect.
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(DesignTokens.TextColor.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

private struct ColorBody: View {
    let item: ClipItem
    var body: some View {
        let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let color = Color(hex: text) ?? .gray
        let useWhiteText = ColorLuminance.isDark(hex: text)
        ZStack {
            // Match the card shell's corner radius so the swatch reads as a
            // full-card surface rather than a floating tile. A soft shadow
            // tinted with the swatch color gives it the same "floating"
            // feel the text/image cards get from their own shadows.
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: color.opacity(0.25), radius: 8, x: 0, y: 2)
            Text(text.uppercased())
                .font(DesignTokens.mono(13, weight: .bold))
                .foregroundStyle(useWhiteText ? .white : .black)
                .tracking(0.8)
                .shadow(color: (useWhiteText ? Color.black : Color.white).opacity(0.25), radius: 1, x: 0, y: 0)
        }
        .padding(12)
    }
}

/// Helper: perceived luminance from a hex color. Used by color-preview
/// cards to pick black vs white label text so hex codes stay readable on
/// any background.
enum ColorLuminance {
    /// Returns true if the color should use white foreground text.
    static func isDark(hex: String) -> Bool {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return true }
        let r, g, b: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        }
        // Rec. 709 luma — same formula macOS uses for menu contrast.
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luma < 0.55
    }
}

private struct FileBody: View {
    let item: ClipItem
    var body: some View {
        let urls = item.fileURLs
        let first = urls.first
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                fileIcon(for: first)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(first?.lastPathComponent ?? "file")
                        .font(DesignTokens.rounded(12, weight: .semibold))
                        .foregroundStyle(DesignTokens.TextColor.primary)
                        .lineLimit(2)
                    if urls.count > 1 {
                        Text("+\(urls.count - 1) more")
                            .font(DesignTokens.rounded(10))
                            .foregroundStyle(DesignTokens.TextColor.tertiary)
                    } else if let size = fileSizeText(for: first) {
                        Text(size)
                            .font(DesignTokens.rounded(10))
                            .foregroundStyle(DesignTokens.TextColor.tertiary)
                    }
                }
                Spacer()
            }
            if let path = first?.deletingLastPathComponent().path {
                Text(path)
                    .font(DesignTokens.mono(10))
                    .foregroundStyle(DesignTokens.TextColor.tertiary)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func fileIcon(for url: URL?) -> some View {
        if let url {
            Image(nsImage: AppIconCache.icon(forFile: url, size: 40))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "doc.fill")
                .font(.system(size: 30))
                .foregroundStyle(DesignTokens.TextColor.tertiary)
        }
    }

    private func fileSizeText(for url: URL?) -> String? {
        guard let url,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return SharedFormatters.byteCount.string(fromByteCount: Int64(size))
    }
}

// MARK: - Color(hex:) + theme bridges

extension Color {
    /// Returns a Color that picks a different variant depending on whether
    /// the host appearance is light or dark. Used throughout DesignTokens
    /// so card fills, borders, and overlays adapt without per-view logic.
    init(light: Color, dark: Color) {
        self = Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 3:
            r = Double((value >> 8) & 0xF) / 15
            g = Double((value >> 4) & 0xF) / 15
            b = Double(value & 0xF) / 15
            a = 1
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            return nil
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }
}
