import AppKit
import Observation

/// Builds and wires every component. The only place that knows about all of them.
@MainActor @Observable
final class AppModel {
    let settings: SettingsStore
    let permissions: PermissionsChecker
    let models: ModelManager
    /// Last checked availability of Apple Intelligence (Settings explains the Qwen fallback with it).
    private(set) var appleIntelligence: AppleIntelligenceStatus
    /// The cleanup model actually in use: the Settings choice, or Qwen3 1.7B standing in for Apple Intelligence.
    private(set) var cleanupEngine: CleanupEngine
    @ObservationIgnored let hotkeyMonitor: HotkeyMonitor
    @ObservationIgnored let recorder: AudioRecorder
    @ObservationIgnored let overlay: OverlayController
    @ObservationIgnored let coordinator: DictationCoordinator
    #if DEBUG
    @ObservationIgnored private(set) var playground: UIPlayground!
    #endif

    @ObservationIgnored private var permissionPoll: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let appleIntelligenceStatus: @MainActor () -> AppleIntelligenceStatus
    @ObservationIgnored private let makeCleaner: @MainActor (CleanupEngine) -> any CleanupBackend

    /// `appleIntelligenceStatus` and `makeCleaner` are replaceable for tests.
    init(
        settings: SettingsStore = SettingsStore(),
        appleIntelligenceStatus: @escaping @MainActor () -> AppleIntelligenceStatus = AppleIntelligenceCleaner.currentStatus,
        makeCleaner: @escaping @MainActor (CleanupEngine) -> any CleanupBackend = { $0.makeCleaner() }
    ) {
        self.settings = settings
        self.appleIntelligenceStatus = appleIntelligenceStatus
        self.makeCleaner = makeCleaner
        self.hotkeyMonitor = HotkeyMonitor(hotkey: settings.hotkey)
        // Locals first: `self` can't be used until every stored property is set.
        let permissions = PermissionsChecker()
        let recorder = AudioRecorder()
        let overlay = OverlayController()
        let transcriber = WhisperKitTranscriber(variant: settings.whisperModel.variant)
        let appleIntelligence = appleIntelligenceStatus()
        let cleanupEngine = CleanupEngine.resolve(settings.cleanupModel, appleIntelligence: appleIntelligence)
        let cleaner = makeCleaner(cleanupEngine)
        let models = ModelManager(transcriber: transcriber, cleaner: cleaner, keepWarm: { settings.keepWarm })
        self.permissions = permissions
        self.recorder = recorder
        self.overlay = overlay
        self.models = models
        self.appleIntelligence = appleIntelligence
        self.cleanupEngine = cleanupEngine
        self.coordinator = DictationCoordinator(
            recorder: recorder,
            transcriber: transcriber,
            cleaner: cleaner,
            inserter: PasteboardInserter(pasteboard: SystemPasteboard(), keys: SystemKeySender(), focus: AXFocusProbe()),
            pill: overlay,
            media: SystemMediaPauser(),
            isCleanupEnabled: { settings.cleanupEnabled },
            isIncrementalEnabled: { settings.transcribeWhileSpeaking },
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
        coordinator.onRecordingStarted = { [weak self] in
            // Picks up Apple Intelligence being turned on or off in System Settings since the last dictation.
            self?.refreshCleanupEngine()
            self?.models.warmUp()
        }
        coordinator.onDictationProcessed = { [weak self] in self?.models.touch() }
        if permissions.microphone == .notDetermined {
            Task { await permissions.requestMicrophone() }
        }
        models.prepareAll()
        warmUpAfterWake()
        startHotkeyWhenTrusted()
    }

    /// Sleep leaves the models loaded but cold: warm them as the Mac wakes, before the first dictation needs them.
    private func warmUpAfterWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.models.notice("woke from sleep; warming models")
                self?.models.warmUp()
            }
        }
    }

    // MARK: - Model switching (used by Settings)

    func switchWhisperModel() {
        let transcriber = WhisperKitTranscriber(variant: settings.whisperModel.variant)
        coordinator.transcriber = transcriber
        models.replace(.transcriber, with: transcriber)
    }

    func switchCleanupModel() {
        refreshCleanupEngine()
    }

    /// Re-checks Apple Intelligence and swaps the cleanup model if the one that should run has changed
    /// (spec §11 amendment 8). Cheap; called on Settings changes, when Settings opens and when a recording starts.
    func refreshCleanupEngine() {
        let status = appleIntelligenceStatus()
        if status != appleIntelligence { appleIntelligence = status }
        let engine = CleanupEngine.resolve(settings.cleanupModel, appleIntelligence: status)
        guard engine != cleanupEngine else { return }
        Log.models.notice("cleanup model: \(String(describing: engine), privacy: .public) (Apple Intelligence \(String(describing: status), privacy: .public))")
        cleanupEngine = engine
        let cleaner = makeCleaner(engine)
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
