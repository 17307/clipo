import AppKit
import Defaults
import SwiftUI

struct ClipPreviewView: View {
    let item: ClipItem
    let onClose: () -> Void

    @Default(.accentColorHex) private var accentHex
    private var accent: Color { Color(hex: accentHex) ?? DesignTokens.accent }

    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()
            Color.white.opacity(0.40).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Divider().opacity(0.25)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().opacity(0.25)
                footer
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if let app = sourceAppInfo {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(DesignTokens.rounded(13, weight: .semibold))
                        .foregroundStyle(DesignTokens.TextColor.primary)
                    Text(relativeTime)
                        .font(DesignTokens.rounded(10))
                        .foregroundStyle(DesignTokens.TextColor.tertiary)
                }
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 16))
                    .foregroundStyle(DesignTokens.TextColor.secondary)
                Text("Clipboard item")
                    .font(DesignTokens.rounded(13, weight: .semibold))
                    .foregroundStyle(DesignTokens.TextColor.primary)
            }

            Spacer()

            typeChip

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DesignTokens.TextColor.tertiary)
            }
            .buttonStyle(.plain)
            .pointingHand()
            .accessibilityLabel("Close preview")
            .help("Close preview")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var typeChip: some View {
        let (label, icon) = typeLabelAndIcon
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(label).font(DesignTokens.rounded(10, weight: .semibold)).tracking(0.3)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(accent)
        .background(Capsule().fill(accent.opacity(0.12)))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch item.primaryKind {
        case .text:  textContent
        case .url:   urlContent
        case .image: imageContent
        case .color: colorContent
        case .file:  fileContent
        }
    }

    /// Soft cap on preview characters — larger copies are truncated so a
    /// multi-megabyte clipboard doesn't block the main thread on layout.
    private static let previewCharLimit = 200_000

    private var textContent: some View {
        let raw = item.previewableText
        let wasTruncated = raw.count > Self.previewCharLimit
        let display: String = {
            guard wasTruncated else { return raw }
            let prefix = String(raw.prefix(Self.previewCharLimit))
            return prefix + "\n\n… truncated — \(raw.count.formatted()) chars total."
        }()
        return VStack(spacing: 0) {
            ScrollableTextView(
                text: display,
                font: .systemFont(ofSize: 13),
                insets: NSSize(width: 22, height: 18)
            )
        }
    }

    private var urlContent: some View {
        let url = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let components = URL(string: url)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(components?.host ?? "link")
                        .font(DesignTokens.rounded(16, weight: .semibold))
                        .foregroundStyle(DesignTokens.TextColor.primary)
                    Text(components?.path.isEmpty == false ? (components?.path ?? "") : "/")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DesignTokens.TextColor.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            Text(url)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DesignTokens.TextColor.primary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.04)))

            HStack {
                Button {
                    if let c = components { NSWorkspace.shared.open(c) }
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                Spacer()
            }
        }
        .padding(22)
    }

    private var imageContent: some View {
        Group {
            if let img = item.image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(minWidth: 200, minHeight: 200)
                        .padding(18)
                }
            } else {
                Text("Image could not be decoded.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var colorContent: some View {
        let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let color = Color(hex: text) ?? .gray
        return HStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color)
                .frame(width: 220, height: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: color.opacity(0.35), radius: 20, x: 0, y: 8)

            VStack(alignment: .leading, spacing: 10) {
                infoRow(title: "HEX", value: text.uppercased())
                if let rgb = rgbComponents(hex: text) {
                    infoRow(title: "RGB", value: "\(rgb.r), \(rgb.g), \(rgb.b)")
                    infoRow(title: "RGB %", value: String(
                        format: "%.0f, %.0f, %.0f",
                        Double(rgb.r) / 2.55,
                        Double(rgb.g) / 2.55,
                        Double(rgb.b) / 2.55
                    ))
                }
                Spacer()
            }

            Spacer()
        }
        .padding(22)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(DesignTokens.rounded(10, weight: .bold))
                .foregroundStyle(DesignTokens.TextColor.tertiary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.TextColor.primary)
                .textSelection(.enabled)
        }
    }

    private var fileContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(item.fileURLs, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                                .font(DesignTokens.rounded(13, weight: .medium))
                                .foregroundStyle(DesignTokens.TextColor.primary)
                            Text(url.deletingLastPathComponent().path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(DesignTokens.TextColor.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.04)))
                }
            }
            .padding(18)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            hintItem(key: "space", text: "Close")
            hintItem(key: "esc", text: "Close")
            Spacer()
            if let stat = statString {
                Text(stat)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignTokens.TextColor.secondary)
            }
            if item.numberOfCopies > 1 {
                Text("copied \(item.numberOfCopies)×")
                    .font(DesignTokens.rounded(10, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func hintItem(key: String, text: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(DesignTokens.rounded(9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.08)))
            Text(text)
                .font(DesignTokens.rounded(10))
        }
        .foregroundStyle(DesignTokens.TextColor.tertiary)
    }

    // MARK: - Derived values

    private var sourceAppInfo: (name: String, icon: NSImage)? {
        guard let id = item.sourceAppBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
              let icon = AppIconCache.icon(forBundleID: id, size: 22) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return (name, icon)
    }

    private var relativeTime: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        fmt.dateTimeStyle = .named
        return fmt.localizedString(for: item.lastCopiedAt, relativeTo: .now)
    }

    private var typeLabelAndIcon: (String, String) {
        switch item.primaryKind {
        case .text:  return ("TEXT",  "doc.text")
        case .url:   return ("LINK",  "link")
        case .image: return ("IMAGE", "photo")
        case .color: return ("COLOR", "paintpalette.fill")
        case .file:  return ("FILE",  "doc.fill")
        }
    }

    private var statString: String? {
        switch item.primaryKind {
        case .image:
            if let img = item.image { return "\(Int(img.size.width))×\(Int(img.size.height))" }
            return nil
        case .file:
            let n = item.fileURLs.count
            return "\(n) file\(n == 1 ? "" : "s")"
        case .text, .url, .color:
            if let t = item.text { return "\(t.count) chars" }
            return nil
        }
    }

    private func rgbComponents(hex: String) -> (r: Int, g: Int, b: Int)? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        return (Int((v >> 16) & 0xFF), Int((v >> 8) & 0xFF), Int(v & 0xFF))
    }
}
