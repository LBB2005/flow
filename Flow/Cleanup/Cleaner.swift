protocol Cleaner: Sendable {
    func clean(_ transcript: String) async throws -> String
}

/// Used until the real model is wired in (Phase 2) and when cleanup is unavailable.
struct PassthroughCleaner: Cleaner {
    func clean(_ transcript: String) async throws -> String { transcript }
}
