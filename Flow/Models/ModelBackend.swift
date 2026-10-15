import Foundation

/// A downloadable, loadable local model (Whisper or the cleanup LLM).
protocol ModelBackend: Sendable {
    var displayName: String { get }
    func isDownloaded() async -> Bool
    func download(progress: @escaping @Sendable (Double) -> Void) async throws
    func load() async throws
    func unload() async
}

enum ModelError: LocalizedError {
    case notDownloaded

    var errorDescription: String? {
        switch self {
        case .notDownloaded: "The model hasn't been downloaded yet."
        }
    }
}

enum ModelPaths {
    /// ~/Library/Application Support/Flow/Models
    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Flow/Models", directoryHint: .isDirectory)
    }
}
