import Foundation

struct TimeoutError: Error {}

/// Runs `operation`, but gives up after `timeout` even if the operation ignores
/// cancellation (MLX generation can't always be interrupted mid-token).
func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let gate = ResumeOnce(continuation)
        let work = Task {
            do { gate.resume(with: .success(try await operation())) }
            catch { gate.resume(with: .failure(error)) }
        }
        Task {
            try? await Task.sleep(for: timeout)
            work.cancel()
            gate.resume(with: .failure(TimeoutError()))
        }
    }
}

private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    func resume(with result: Result<T, Error>) {
        let pending: CheckedContinuation<T, Error>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}
