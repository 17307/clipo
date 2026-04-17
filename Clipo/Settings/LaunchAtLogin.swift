import Foundation
import ServiceManagement
import SwiftUI

/// Minimal wrapper over `SMAppService.mainApp` for toggling launch-at-login.
/// Replaces the (network-fetched) sindresorhus/LaunchAtLogin package.
enum LaunchAtLoginHelper {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            // SMAppService logs the error; nothing we can do from here.
        }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var isEnabled: Bool = LaunchAtLoginHelper.isEnabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { isEnabled },
            set: { new in
                LaunchAtLoginHelper.setEnabled(new)
                // SMAppService may take a moment; reread the status.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isEnabled = LaunchAtLoginHelper.isEnabled
                }
            }
        ))
    }
}
