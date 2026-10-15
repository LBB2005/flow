import Foundation
import Observation

/// Builds and wires every component. The only place that knows about all of them.
@MainActor @Observable
final class AppModel {
    let settings: SettingsStore
    let permissions = PermissionsChecker()
    @ObservationIgnored let hotkeyMonitor: HotkeyMonitor

    @ObservationIgnored private var permissionPoll: Task<Void, Never>?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        self.hotkeyMonitor = HotkeyMonitor(hotkey: settings.hotkey)
    }

    func start() {
        guard !AppEnvironment.isRunningTests else { return }
        permissions.refresh()
        hotkeyMonitor.onAction = { action in
            Log.hotkey.info("hotkey action: \(String(describing: action))")
        }
        startHotkeyWhenTrusted()
    }

    /// Polls every 2 s until Accessibility is granted, then installs the event tap.
    private func startHotkeyWhenTrusted() {
        permissionPoll?.cancel()
        permissionPoll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.permissions.refresh()
                if self.permissions.accessibility && self.hotkeyMonitor.start() { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
