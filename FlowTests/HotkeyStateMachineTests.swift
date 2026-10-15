import Testing
@testable import Flow

struct HotkeyStateMachineTests {
    private func run(_ inputs: [HotkeyInput]) -> [HotkeyAction?] {
        var machine = HotkeyStateMachine()
        return inputs.map { machine.handle($0) }
    }

    // Tap mode: a quick press latches hands-free recording; the next press stops it.

    @Test func quickTapLatchesThenNextPressFinishes() {
        #expect(run([.hotkeyDown(at: 0), .hotkeyUp(at: 0.1), .hotkeyDown(at: 5), .hotkeyUp(at: 5.1)])
                == [.begin, .confirm, .finish, nil])
    }

    @Test func otherInputWhileLatchedIsIgnored() {
        // Clicking into a text box or typing while hands-free must not cancel the recording.
        #expect(run([.hotkeyDown(at: 0), .hotkeyUp(at: 0.1), .otherInput(at: 1), .hotkeyDown(at: 2)])
                == [.begin, .confirm, nil, .finish])
    }

    @Test func escapeCancelsLatchedRecording() {
        #expect(run([.hotkeyDown(at: 0), .hotkeyUp(at: 0.1), .escape(at: 1), .hotkeyUp(at: 2)])
                == [.begin, .confirm, .cancel(.escape), nil])
    }

    @Test func tickWhileLatchedDoesNothing() {
        #expect(run([.hotkeyDown(at: 0), .hotkeyUp(at: 0.1), .tick(at: 0.3)]) == [.begin, .confirm, nil])
    }

    // Hold mode: push-to-talk.

    @Test func holdConfirmsThenReleaseFinishes() {
        #expect(run([.hotkeyDown(at: 0), .tick(at: 0.1), .tick(at: 0.31), .hotkeyUp(at: 2)])
                == [.begin, nil, .confirm, .finish])
    }

    @Test func tickExactlyAtThresholdConfirms() {
        #expect(run([.hotkeyDown(at: 1), .tick(at: 1.3)]) == [.begin, .confirm])
    }

    @Test func releaseAfterThresholdWithoutTickStillFinishes() {
        #expect(run([.hotkeyDown(at: 0), .hotkeyUp(at: 0.5)]) == [.begin, .finish])
    }

    @Test func repeatedDownWhileHeldIsIgnored() {
        #expect(run([.hotkeyDown(at: 0), .hotkeyDown(at: 0.05), .tick(at: 0.3), .hotkeyDown(at: 0.4)])
                == [.begin, nil, .confirm, nil])
    }

    @Test func otherInputWhilePendingCancelsAsChord() {
        // e.g. Right ⌥ + E to type an accent, or ⌥-click in Finder.
        #expect(run([.hotkeyDown(at: 0), .otherInput(at: 0.1), .hotkeyUp(at: 0.2)])
                == [.begin, .cancel(.chord), nil])
    }

    @Test func otherInputWhileHoldingCancelsAsChord() {
        #expect(run([.hotkeyDown(at: 0), .tick(at: 0.3), .otherInput(at: 1), .hotkeyUp(at: 2)])
                == [.begin, .confirm, .cancel(.chord), nil])
    }

    @Test func escapeWhileHoldingCancels() {
        #expect(run([.hotkeyDown(at: 0), .tick(at: 0.3), .escape(at: 1), .hotkeyUp(at: 2)])
                == [.begin, .confirm, .cancel(.escape), nil])
    }

    // General

    @Test func inputsWhileIdleDoNothing() {
        #expect(run([.hotkeyUp(at: 0), .tick(at: 1), .otherInput(at: 2), .escape(at: 3)])
                == [nil, nil, nil, nil])
    }

    @Test func machineIsReusableAfterEachMode() {
        #expect(run([.hotkeyDown(at: 0), .hotkeyUp(at: 1),                       // hold
                     .hotkeyDown(at: 5), .hotkeyUp(at: 5.05), .hotkeyDown(at: 8), // tap, tap
                     .hotkeyDown(at: 9)])
                == [.begin, .finish, .begin, .confirm, .finish, .begin])
    }

    @Test func resetReturnsToIdle() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        _ = machine.handle(.hotkeyUp(at: 0.1))
        #expect(machine.phase == .latched)
        machine.reset()
        #expect(machine.phase == .idle)
        #expect(machine.handle(.hotkeyDown(at: 1)) == .begin)
    }

    @Test func isEngagedTracksPhase() {
        var machine = HotkeyStateMachine()
        #expect(!machine.isEngaged)
        _ = machine.handle(.hotkeyDown(at: 0))
        #expect(machine.isEngaged)
        _ = machine.handle(.hotkeyUp(at: 0.1))
        #expect(machine.isEngaged) // latched
        _ = machine.handle(.hotkeyDown(at: 2))
        #expect(!machine.isEngaged)
    }
}
