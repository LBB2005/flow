import Foundation
@testable import Flow

enum FakeError: Error { case boom }

/// Mutable counter that @MainActor closures can capture safely.
@MainActor final class Counter { var value = 0 }

enum FakeAudio {
    /// One second of a clearly audible tone.
    static let speech: [Float] = (0..<16_000).map { sin(Float($0) * 0.05) * 0.3 }
    static let silence = [Float](repeating: 0, count: 16_000)
}

@MainActor
final class FakeRecorder: Recorder {
    var samplesToReturn: [Float] = FakeAudio.speech
    var startError: Error?
    private(set) var events: [String] = []
    var onMaxDurationReached: (@MainActor () -> Void)?

    func start() throws {
        if let startError { throw startError }
        events.append("start")
    }
    func stop() -> [Float] { events.append("stop"); return samplesToReturn }
    func cancel() { events.append("cancel") }
}

final class FakeTranscriber: Transcriber, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private let result: Result<String, Error>

    init(_ result: Result<String, Error>) { self.result = result }

    var calls: Int { lock.withLock { _calls } }

    func transcribe(_ samples: [Float]) async throws -> String {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

final class FakeCleaner: Cleaner, @unchecked Sendable {
    enum Behavior: Sendable { case returns(String), fails, hangs }
    private let lock = NSLock()
    private var _calls = 0
    private let behavior: Behavior

    init(_ behavior: Behavior) { self.behavior = behavior }

    var calls: Int { lock.withLock { _calls } }

    func clean(_ transcript: String) async throws -> String {
        lock.withLock { _calls += 1 }
        switch behavior {
        case .returns(let text): return text
        case .fails: throw FakeError.boom
        case .hangs:
            try await Task.sleep(for: .seconds(60))
            return "too late"
        }
    }
}

@MainActor
final class FakeInserter: TextInserter {
    var result: InsertResult = .pasted
    private(set) var inserted: [String] = []
    func insert(_ text: String) async -> InsertResult {
        inserted.append(text)
        return result
    }
}

@MainActor
final class FakePill: PillPresenter {
    private(set) var shown: [PillState] = []
    private(set) var hideCount = 0
    func show(_ state: PillState) { shown.append(state) }
    func hide() { hideCount += 1 }
}
