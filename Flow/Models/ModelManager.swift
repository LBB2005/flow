import Foundation
import Observation

/// Owns model lifecycle: check → download → load → keep warm → unload when idle (spec §5).
@MainActor @Observable
final class ModelManager {
    enum Kind: CaseIterable, Sendable { case transcriber, cleaner }

    enum Status: Equatable, Sendable {
        case checking
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var statuses: [Kind: Status] = [.transcriber: .checking, .cleaner: .checking]

    @ObservationIgnored private var backends: [Kind: any ModelBackend]
    @ObservationIgnored private var prepareTasks: [Kind: Task<Void, Never>] = [:]
    @ObservationIgnored private let idleTimer: IdleTimer
    @ObservationIgnored private let keepWarm: @MainActor () -> KeepWarm

    init(
        transcriber: any ModelBackend,
        cleaner: any ModelBackend,
        keepWarm: @escaping @MainActor () -> KeepWarm,
        idleTimer: IdleTimer = IdleTimer()
    ) {
        self.backends = [.transcriber: transcriber, .cleaner: cleaner]
        self.keepWarm = keepWarm
        self.idleTimer = idleTimer
    }

    func status(of kind: Kind) -> Status { statuses[kind] ?? .checking }

    func prepareAll() {
        for kind in Kind.allCases { prepare(kind) }
    }

    /// Downloads the model if needed, then loads it and starts the keep-warm countdown.
    @discardableResult
    func prepare(_ kind: Kind) -> Task<Void, Never> {
        prepareTasks[kind]?.cancel()
        guard let backend = backends[kind] else { return Task {} }
        let task = Task { [weak self] in
            guard let self else { return }
            self.statuses[kind] = .checking
            do {
                if !(await backend.isDownloaded()) {
                    self.statuses[kind] = .downloading(0)
                    Log.models.info("downloading \(backend.displayName)")
                    try await backend.download { fraction in
                        Task { @MainActor [weak self] in
                            guard let self, case .downloading = self.statuses[kind] else { return }
                            self.statuses[kind] = .downloading(fraction)
                        }
                    }
                }
                try Task.checkCancellation()
                try await backend.load()
                self.statuses[kind] = .ready
                self.touch()
                Log.models.notice("\(backend.displayName, privacy: .public) ready")
            } catch is CancellationError {
                return
            } catch {
                Log.models.error("\(backend.displayName) failed: \(error.localizedDescription)")
                self.statuses[kind] = .failed(error.localizedDescription)
            }
        }
        prepareTasks[kind] = task
        return task
    }

    /// Swaps in a different model (settings change): unloads the old one and prepares the new one.
    @discardableResult
    func replace(_ kind: Kind, with backend: any ModelBackend) -> Task<Void, Never> {
        let old = backends[kind]
        backends[kind] = backend
        Task { await old?.unload() }
        return prepare(kind)
    }

    /// Call when a recording starts: loads every ready model in the background (a no-op for models still loaded)
    /// so a reload after the keep-warm unload overlaps with the user speaking, and restarts the keep-warm countdown.
    /// Models that are still checking, downloading or failed are left to `prepare`.
    @discardableResult
    func warmUp() -> Task<Void, Never> {
        touch()
        let targets = Kind.allCases.filter { status(of: $0) == .ready }.compactMap { backends[$0] }
        return Task {
            await withTaskGroup(of: Void.self) { group in
                for backend in targets {
                    group.addTask {
                        do {
                            try await backend.load()
                        } catch {
                            Log.models.error("warm-up of \(backend.displayName, privacy: .public) failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    /// Call after every dictation: restarts the keep-warm countdown.
    func touch() {
        idleTimer.restart(after: keepWarm().duration) { [weak self] in
            await self?.unloadAll()
        }
    }

    func unloadAll() async {
        Log.models.notice("keep-warm expired; unloading models")
        for backend in backends.values { await backend.unload() }
    }
}
