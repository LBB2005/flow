import Foundation
import Observation

enum KeepWarm: String, CaseIterable, Codable, Sendable, Identifiable {
    case twoMinutes, tenMinutes, thirtyMinutes, always

    var id: String { rawValue }

    /// How long models stay loaded after the last dictation. `nil` = never unload.
    var duration: Duration? {
        switch self {
        case .twoMinutes: .seconds(120)
        case .tenMinutes: .seconds(600)
        case .thirtyMinutes: .seconds(1800)
        case .always: nil
        }
    }

    var label: String {
        switch self {
        case .twoMinutes: "2 minutes"
        case .tenMinutes: "10 minutes"
        case .thirtyMinutes: "30 minutes"
        case .always: "Always"
        }
    }
}

enum WhisperModelChoice: String, CaseIterable, Sendable, Identifiable {
    case largeV3Turbo = "large-v3-v20240930_626MB"
    case base = "base"

    var id: String { rawValue }
    var variant: String { rawValue }

    var label: String {
        switch self {
        case .largeV3Turbo: "Large v3 Turbo: most accurate (~630 MB)"
        case .base: "Base: fastest, less accurate (~150 MB)"
        }
    }
}

enum CleanupModelChoice: String, CaseIterable, Sendable, Identifiable {
    case qwen3_1_7b = "mlx-community/Qwen3-1.7B-4bit"
    case qwen3_4b = "mlx-community/Qwen3-4B-4bit"

    var id: String { rawValue }
    var repoID: String { rawValue }

    var label: String {
        switch self {
        case .qwen3_1_7b: "Qwen3 1.7B: fast (~1 GB)"
        case .qwen3_4b: "Qwen3 4B: better quality (~2.3 GB)"
        }
    }
}

@MainActor @Observable
final class SettingsStore {
    private enum Keys {
        static let hotkey = "hotkey"
        static let microphoneUID = "microphoneUID"
        static let whisperModel = "whisperModel"
        static let cleanupModel = "cleanupModel"
        static let cleanupEnabled = "cleanupEnabled"
        static let keepWarm = "keepWarm"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var hotkey: Hotkey {
        didSet { defaults.set(try? JSONEncoder().encode(hotkey), forKey: Keys.hotkey) }
    }
    /// CoreAudio device UID; nil = system default input.
    var microphoneUID: String? {
        didSet { defaults.set(microphoneUID, forKey: Keys.microphoneUID) }
    }
    var whisperModel: WhisperModelChoice {
        didSet { defaults.set(whisperModel.rawValue, forKey: Keys.whisperModel) }
    }
    var cleanupModel: CleanupModelChoice {
        didSet { defaults.set(cleanupModel.rawValue, forKey: Keys.cleanupModel) }
    }
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }
    var keepWarm: KeepWarm {
        didSet { defaults.set(keepWarm.rawValue, forKey: Keys.keepWarm) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotkey = defaults.data(forKey: Keys.hotkey)
            .flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) } ?? .default
        microphoneUID = defaults.string(forKey: Keys.microphoneUID)
        whisperModel = defaults.string(forKey: Keys.whisperModel)
            .flatMap(WhisperModelChoice.init(rawValue:)) ?? .largeV3Turbo
        cleanupModel = defaults.string(forKey: Keys.cleanupModel)
            .flatMap(CleanupModelChoice.init(rawValue:)) ?? .qwen3_1_7b
        cleanupEnabled = defaults.object(forKey: Keys.cleanupEnabled) as? Bool ?? true
        keepWarm = defaults.string(forKey: Keys.keepWarm)
            .flatMap(KeepWarm.init(rawValue:)) ?? .tenMinutes
    }
}
