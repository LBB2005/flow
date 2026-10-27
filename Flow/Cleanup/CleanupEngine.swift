/// A cleaner that `ModelManager` can also load and unload.
typealias CleanupBackend = Cleaner & ModelBackend

/// Which cleanup model actually runs: the Settings choice, unless that's Apple Intelligence and it's
/// unavailable, in which case Qwen3 1.7B stands in (spec §11 amendment 8).
enum CleanupEngine: Equatable, Sendable {
    case appleIntelligence
    case mlx(repoID: String)

    /// Used when Apple Intelligence is chosen but unavailable.
    static let fallback = CleanupEngine.mlx(repoID: CleanupModelChoice.qwen3_1_7b.repoID)

    static func resolve(_ choice: CleanupModelChoice, appleIntelligence: AppleIntelligenceStatus) -> CleanupEngine {
        switch choice {
        case .appleIntelligence: appleIntelligence == .available ? .appleIntelligence : fallback
        case .qwen3_1_7b, .qwen3_4b: .mlx(repoID: choice.repoID)
        }
    }

    func makeCleaner() -> any CleanupBackend {
        switch self {
        case .appleIntelligence: AppleIntelligenceCleaner()
        case .mlx(let repoID): MLXCleaner(repoID: repoID)
        }
    }
}
