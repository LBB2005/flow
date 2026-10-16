import Foundation
import Observation

/// Builds and wires every component. The only place that knows about all of them.
@MainActor @Observable
final class AppModel {
    let settings: SettingsStore
    let permissions: PermissionsChecker
    let models: ModelManager
    @ObservationIgnored let hotkeyMonitor: HotkeyMonitor
    @ObservationIgnored let recorder: AudioRecorder
    @ObservationIgnored let overlay: OverlayController
    @ObservationIgnored let coordinator: DictationCoordinator
    #if DEBUG
    @ObservationIgnored private(set) var playground: UIPlayground!
    #endif

    @ObservationIgnored private var permissionPoll: Task<Void, Never>?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        self.hotkeyMonitor = HotkeyMonitor(hotkey: settings.hotkey)
        // Locals first: `self` can't be used until every stored property is set.
        let permissions = PermissionsChecker()
        let recorder = AudioRecorder()
        let overlay = OverlayController()
        let transcriber = WhisperKitTranscriber(variant: settings.whisperModel.variant)
        let cleaner = MLXCleaner(repoID: settings.cleanupModel.repoID)
        let models = ModelManager(transcriber: transcriber, cleaner: cleaner, keepWarm: { settings.keepWarm })
        self.permissions = permissions
        self.recorder = recorder
        self.overlay = overlay
        self.models = models
        self.coordinator = DictationCoordinator(
            recorder: recorder,
            transcriber: transcriber,
            cleaner: cleaner,
            inserter: PasteboardInserter(pasteboard: SystemPasteboard(), keys: SystemKeySender(), focus: AXFocusProbe()),
            pill: overlay,
            isCleanupEnabled: { settings.cleanupEnabled },
            blockedReason: { Self.blockedReason(permissions: permissions, models: models) }
        )
        #if DEBUG
        playground = UIPlayground(overlay: overlay)
        #endif
    }

    func start() {
        guard !AppEnvironment.isRunningTests else { return }
        #if DEBUG
        // `open Flow.app --args --playground`: demo the overlay without permissions or recording.
        if CommandLine.arguments.contains("--playground") {
            playground.playAll()
            return
        }
        #endif
        permissions.refresh()
        recorder.preferredDeviceUID = settings.microphoneUID
        recorder.onLevel = { [weak self] level in self?.overlay.push(level: level) }
        hotkeyMonitor.onAction = { [weak self] action in self?.coordinator.handle(action) }
        coordinator.onAutoStop = { [weak self] in self?.hotkeyMonitor.resetGesture() }
        coordinator.onRecordingStarted = { [weak self] in self?.models.warmUp() }
        coordinator.onDictationProcessed = { [weak self] in self?.models.touch() }
        if permissions.microphone == .notDetermined {
            Task { await permissions.requestMicrophone() }
        }
        models.prepareAll()
        startHotkeyWhenTrusted()
    }

    // MARK: - Model switching (used by Settings)

    func switchWhisperModel() {
        let transcriber = WhisperKitTranscriber(variant: settings.whisperModel.variant)
        coordinator.transcriber = transcriber
        models.replace(.transcriber, with: transcriber)
    }

    func switchCleanupModel() {
        let cleaner = MLXCleaner(repoID: settings.cleanupModel.repoID)
        coordinator.cleaner = cleaner
        models.replace(.cleaner, with: cleaner)
    }

    // MARK: - Status for the menu

    /// Why dictation can't start right now, or nil if it can.
    static func blockedReason(permissions: PermissionsChecker, models: ModelManager) -> String? {
        if permissions.microphone != .granted { return "Microphone access needed" }
        switch models.status(of: .transcriber) {
        case .ready: return nil
        case .downloading(let fraction): return "Downloading models… \(Int(fraction * 100))%"
        case .failed: return "Model download failed. See the menu"
        case .checking, .notDownloaded: return "Models not ready yet"
        }
    }

    var menuBarSymbol: String {
        if !permissions.allGranted { return "exclamationmark.triangle" }
        if case .downloading = models.status(of: .transcriber) { return "arrow.down.circle" }
        return "waveform"
    }

    var statusLine: String {
        Self.blockedReason(permissions: permissions, models: models)
            ?? "Ready: tap or hold \(settings.hotkey.displayName) to dictate"
    }

    /// Polls every 2 s until Accessibility is granted, then installs the event tap.
    private func startHotkeyWhenTrusted() {
        permissionPoll?.cancel()
        permissionPoll = Task { [weak self] in
            var loggedWaiting = false
            while !Task.isCancelled {
                guard let self else { return }
                self.permissions.refresh()
                if self.permissions.accessibility && self.hotkeyMonitor.start() { return }
                if !loggedWaiting {
                    Log.hotkey.notice("waiting for Accessibility permission (microphone: \(String(describing: self.permissions.microphone)))")
                    loggedWaiting = true
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
