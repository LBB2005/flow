/// Restartable countdown used for the keep-warm window.
@MainActor
final class IdleTimer {
    private let sleep: @Sendable (Duration) async -> Void
    private var task: Task<Void, Never>?

    init(sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Cancels any pending countdown and starts a new one. `nil` = never fire.
    func restart(after delay: Duration?, action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        guard let delay else {
            task = nil
            return
        }
        task = Task { [sleep] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
