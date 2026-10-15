import Foundation
import Observation

/// Builds and wires every component. The only place that knows about all of them.
@MainActor @Observable
final class AppModel {
    let settings: SettingsStore
    let permissions: PermissionsChecker
    @ObservationIgnored let hotkeyMonitor: HotkeyMonitor
    @ObservationIgnored let recorder: AudioRecorder
    @ObservationIgnored let pill: PillPresenter
    @ObservationIgnored let coordinator: DictationCoordinator

    @ObservationIgnored private var permissionPoll: Task<Void, Never>?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        self.hotkeyMonitor = HotkeyMonitor(hotkey: settings.hotkey)
        // Locals first: `self` can't be used until every stored property is set.
        let permissions = PermissionsChecker()
        let recorder = AudioRecorder()
        let pill = LogPillPresenter()
        self.permissions = permissions
        self.recorder = recorder
        self.pill = pill
        self.coordinator = DictationCoordinator(
            recorder: recorder,
            transcriber: PlaceholderTranscriber(),
            cleaner: PassthroughCleaner(),
            inserter: PasteboardInserter(pasteboard: SystemPasteboard(), keys: SystemKeySender(), focus: AXFocusProbe()),
            pill: pill,
            isCleanupEnabled: { settings.cleanupEnabled },
            blockedReason: { permissions.microphone == .granted ? nil : "Microphone access needed" }
        )
    }

    func start() {
        guard !AppEnvironment.isRunningTests else { return }
        permissions.refresh()
        recorder.preferredDeviceUID = settings.microphoneUID
        recorder.prepare()
        hotkeyMonitor.onAction = { [weak self] action in self?.coordinator.handle(action) }
        if permissions.microphone == .notDetermined {
            Task { await permissions.requestMicrophone() }
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
