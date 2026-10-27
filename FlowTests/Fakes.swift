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
    var onSamples: (@MainActor ([Float]) -> Void)?

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
    private(set) var inserted: [String] = []
    func insert(_ text: String) async {
        inserted.append(text)
    }
}

@MainActor
final class FakeMediaPauser: MediaPauser {
    private(set) var events: [String] = []
    /// What the inserter had pasted when `resume()` ran, to check resume comes after the paste.
    private(set) var insertedAtResume: [String]?
    var inserter: FakeInserter?

    func pause() { events.append("pause") }
    func resume() {
        events.append("resume")
        insertedAtResume = inserter?.inserted
    }
}

@MainActor
final class FakePill: PillPresenter {
    private(set) var shown: [PillState] = []
    private(set) var hideCount = 0
    func show(_ state: PillState) { shown.append(state) }
    func hide() { hideCount += 1 }
}

/// Records every call and answers "p1", "p2", … in order; can fail or wait for the test to let it finish.
final class ScriptedTranscriber: Transcriber, @unchecked Sendable {
    struct Call: Equatable { let sampleCount: Int; let context: String? }
    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _cancelled = 0
    private let failOnCall: Int?
    private let gate: Gate?

    init(failOnCall: Int? = nil, gate: Gate? = nil) {
        self.failOnCall = failOnCall
        self.gate = gate
    }

    var calls: [Call] { lock.withLock { _calls } }
    /// Calls that ended because their task was cancelled.
    var cancelled: Int { lock.withLock { _cancelled } }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await transcribe(samples, context: nil)
    }

    func transcribe(_ samples: [Float], context: String?) async throws -> String {
        let number = lock.withLock {
            _calls.append(Call(sampleCount: samples.count, context: context))
            return _calls.count
        }
        if let gate { await gate.wait() }
        if Task.isCancelled {
            lock.withLock { _cancelled += 1 }
            throw CancellationError()
        }
        if number == failOnCall { throw FakeError.boom }
        return "p\(number)"
    }
}
