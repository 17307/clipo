import AppKit
import Defaults
import SwiftUI

struct AppearancePane: View {
    @Default(.menuBarIcon) private var menuBarIcon
    @Default(.accentColorHex) private var accentColorHex
    @Default(.panelHeight) private var panelHeight
    @Default(.panelBottomInset) private var panelBottomInset
    @Default(.showSourceIcon) private var showSourceIcon
    @Default(.showFooterHints) private var showFooterHints

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Icon", selection: $menuBarIcon) {
                    ForEach(MenuBarIcon.allCases) { icon in
                        HStack {
                            Image(systemName: icon.rawValue)
                            Text(icon.label)
                        }
                        .tag(icon)
                    }
                }
            }

            Section("Theme") {
                HStack {
                    Text("Accent color")
                    Spacer()
                    ColorPicker("", selection: accentBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 60)
                }
                Text("Used for selected card border, Pinboard tabs, and highlights.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Panel") {
                Stepper(value: $panelHeight, in: 280...600, step: 10) {
                    HStack {
                        Text("Height")
                        Spacer()
                        Text("\(Int(panelHeight)) pt")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $panelBottomInset, in: 0...40, step: 2) {
                    HStack {
                        Text("Bottom inset")
                        Spacer()
                        Text("\(Int(panelBottomInset)) pt")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Takes effect the next time the panel opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cards") {
                Toggle("Show source app icon on cards", isOn: $showSourceIcon)
                Toggle("Show footer hint bar", isOn: $showFooterHints)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var accentBinding: Binding<Color> {
        Binding<Color>(
            get: { Color(hex: accentColorHex) ?? .orange },
            set: { newColor in accentColorHex = newColor.toHex() ?? "#FF6A3D" }
        )
    }
}

private extension Color {
    func toHex() -> String? {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
