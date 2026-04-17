import AppKit
import Defaults
import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.accentColorHex) private var accentHex

    // Intentionally NOT subscribing to AppState here — `isOptionDown`'s
    // cascading observation used to re-render every visible card. Only the
    // nested `IndexBadge` view watches that flag now.

    private var accent: Color { Color(hex: accentHex) ?? DesignTokens.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(item: item, index: index)
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
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .scaleEffect(scaleFactor)
        .shadow(
            color: isSelected ? accent.opacity(0.30) : .black.opacity(0.10),
            radius: isSelected ? 14 : 5,
            x: 0, y: isSelected ? 6 : 2
        )
        .animation(reduceMotion ? nil : DesignTokens.selectSpring, value: isSelected)
        .animation(reduceMotion ? nil : DesignTokens.hoverAnim, value: isHovering)
        .onHover { isHovering = $0 }
        .pointingHand()
    }

    private var scaleFactor: CGFloat {
        if isSelected { return 1.04 }
        if isHovering { return 1.015 }
        return 1.0
    }

    private var borderColor: Color {
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
    let index: Int

    @Default(.showSourceIcon) private var showSourceIcon

    // Does NOT read AppState. `isOptionDown` changes are isolated to
    // `IndexBadge` so CardHeader itself doesn't re-render each time Option
    // is pressed.

    var body: some View {
        HStack(spacing: 7) {
            if showSourceIcon {
                sourceIcon
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
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
            if index <= 9 {
                IndexBadge(index: index)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var relativeTime: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        fmt.dateTimeStyle = .named
        return fmt.localizedString(for: item.lastCopiedAt, relativeTo: .now)
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let img = Self.icon(for: item.sourceAppBundleID) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(DesignTokens.TextColor.tertiary)
        }
    }

    private var sourceName: String {
        guard let bundle = item.sourceAppBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return "Unknown"
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    fileprivate static func icon(for bundle: String?) -> NSImage? {
        guard let bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return nil
        }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 20, height: 20)
        return img
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
                    .background(Circle().fill(Color.black.opacity(0.08)))
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
            Text(relativeTime)
                .font(DesignTokens.rounded(10, weight: .medium))
                .foregroundStyle(DesignTokens.TextColor.tertiary)
            Spacer(minLength: 4)
            if let stat = statText {
                Text(stat)
                    .font(DesignTokens.mono(9.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.TextColor.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.05)))
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
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        fmt.dateTimeStyle = .named
        return fmt.localizedString(for: item.lastCopiedAt, relativeTo: .now)
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
        let snippet = String(raw.prefix(600))
        Text(snippet.isEmpty ? " " : snippet)
            .font(DesignTokens.rounded(12, weight: .regular))
            .foregroundStyle(DesignTokens.TextColor.primary)
            .lineSpacing(2)
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
        .padding(8)
    }
}

private struct ColorBody: View {
    let item: ClipItem
    var body: some View {
        let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let color = Color(hex: text) ?? .gray
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
            Text(text.uppercased())
                .font(DesignTokens.mono(13, weight: .bold))
                .foregroundStyle(.white)
                .tracking(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.45)))
        }
        .padding(10)
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
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
        return ByteCountFormatter().string(fromByteCount: Int64(size))
    }
}

// MARK: - Color(hex:) bridge

extension Color {
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
