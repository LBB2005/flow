import Testing
@testable import Flow

/// Lets a test decide exactly when "time passes".
actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var waiterCount: Int { waiters.count }
    func wait() async { await withCheckedContinuation { waiters.append($0) } }
    func open() { waiters.forEach { $0.resume() }; waiters.removeAll() }
}

/// Polls until `condition` holds (max ~1 s).
@MainActor
func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

@MainActor
struct IdleTimerTests {
    @Test func firesAfterDelay() async {
        let gate = Gate()
        let timer = IdleTimer(sleep: { _ in await gate.wait() })
        let fired = Counter()
        timer.restart(after: .seconds(600)) { fired.value += 1 }
        #expect(await eventually { await gate.waiterCount == 1 })
        await gate.open()
        #expect(await eventually { fired.value == 1 })
    }

    @Test func restartReplacesPendingCountdown() async {
        let gate = Gate()
        let timer = IdleTimer(sleep: { _ in await gate.wait() })
        let fired = Counter()
        timer.restart(after: .seconds(600)) { fired.value += 1 }
        timer.restart(after: .seconds(600)) { fired.value += 1 }
        #expect(await eventually { await gate.waiterCount == 2 })
        await gate.open()
        #expect(await eventually { fired.value == 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fired.value == 1)
    }

    @Test func nilDelayNeverFires() async {
        let gate = Gate()
        let timer = IdleTimer(sleep: { _ in await gate.wait() })
        let fired = Counter()
        timer.restart(after: nil) { fired.value += 1 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await gate.waiterCount == 0)
        #expect(fired.value == 0)
    }
}
