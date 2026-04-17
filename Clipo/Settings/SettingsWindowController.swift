import AppKit
import SwiftUI

@MainActor
final class ClipoSettingsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsRootView())
        let defaultSize = NSSize(width: 980, height: 680)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipo Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 600)

        // Autosave the frame, but floor it to the default if the restored
        // value is smaller than the current minimum.
        window.setFrameAutosaveName("ClipoSettingsWindow_v2")
        if window.frame.width < window.minSize.width
            || window.frame.height < window.minSize.height {
            window.setContentSize(defaultSize)
        }
        window.center()
        self.init(window: window)
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Category model

enum SettingsCategory: String, Hashable, CaseIterable, Identifiable {
    case general, appearance, storage, pinboards, scripts, ignore, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "General"
        case .appearance: return "Appearance"
        case .storage:    return "Storage"
        case .pinboards:  return "Pinboards"
        case .scripts:    return "Scripts"
        case .ignore:     return "Ignore"
        case .advanced:   return "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .general:    return "Hotkey, paste, search behavior"
        case .appearance: return "Menu bar, accent color, panel size"
        case .storage:    return "History size, content types, clear"
        case .pinboards:  return "Create, rename, reorder collections"
        case .scripts:    return "Built-in + custom JS transforms"
        case .ignore:     return "Exclude apps, pasteboard types, regex"
        case .advanced:   return "Pause monitoring, permissions, reset"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "gearshape.fill"
        case .appearance: return "paintpalette.fill"
        case .storage:    return "externaldrive.fill"
        case .pinboards:  return "pin.fill"
        case .scripts:    return "curlybraces"
        case .ignore:     return "nosign"
        case .advanced:   return "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general:    return .gray
        case .appearance: return .pink
        case .storage:    return .blue
        case .pinboards:  return .orange
        case .scripts:    return .green
        case .ignore:     return .red
        case .advanced:   return .purple
        }
    }
}

// MARK: - Root view

private struct SettingsRootView: View {
    @State private var selection: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { category in
                SettingsSidebarRow(category: category)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle(selection.title)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:    GeneralPane()
        case .appearance: AppearancePane()
        case .storage:    StoragePane()
        case .pinboards:  PinboardsPane().modelContainer(Storage.shared.container)
        case .scripts:    ScriptsPane()
        case .ignore:     IgnorePane()
        case .advanced:   AdvancedPane()
        }
    }
}

// MARK: - Sidebar row

private struct SettingsSidebarRow: View {
    let category: SettingsCategory

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(category.tint.gradient)
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .shadow(color: category.tint.opacity(0.25), radius: 2, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(category.title)
                    .font(.system(size: 13, weight: .medium))
                Text(category.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
