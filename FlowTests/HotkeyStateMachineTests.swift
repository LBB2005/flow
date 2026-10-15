import Testing
@testable import Flow

struct HotkeyStateMachineTests {
    private func run(_ inputs: [HotkeyInput]) -> [HotkeyAction?] {
        var machine = HotkeyStateMachine()
        return inputs.map { machine.handle($0) }
    }

    @Test func quickTapIsDiscarded() {
        #expect(run([.hotkeyDown(at: 0), .hotkeyUp(at: 0.1)]) == [.begin, .discard])
    }

    @Test func holdConfirmsThenFinishes() {
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
        #expect(run([.hotkeyDown(at: 0), .hotkeyDown(at: 0.05)]) == [.begin, nil])
    }

    @Test func otherInputWhilePendingCancelsAsChord() {
        // e.g. Right ⌥ + E to type an accent, or ⌥-click in Finder.
        #expect(run([.hotkeyDown(at: 0), .otherInput(at: 0.1), .hotkeyUp(at: 0.2)])
                == [.begin, .cancel(.chord), nil])
    }

    @Test func otherInputWhileActiveCancelsAsChord() {
        #expect(run([.hotkeyDown(at: 0), .tick(at: 0.3), .otherInput(at: 1), .hotkeyUp(at: 2)])
                == [.begin, .confirm, .cancel(.chord), nil])
    }

    @Test func escapeCancels() {
        #expect(run([.hotkeyDown(at: 0), .tick(at: 0.3), .escape(at: 1), .hotkeyUp(at: 2)])
                == [.begin, .confirm, .cancel(.escape), nil])
    }

    @Test func inputsWhileIdleDoNothing() {
        #expect(run([.hotkeyUp(at: 0), .tick(at: 1), .otherInput(at: 2), .escape(at: 3)])
                == [nil, nil, nil, nil])
    }

    @Test func machineIsReusableAfterFinish() {
        #expect(run([.hotkeyDown(at: 0), .hotkeyUp(at: 1), .hotkeyDown(at: 5), .hotkeyUp(at: 5.05)])
                == [.begin, .finish, .begin, .discard])
    }

    @Test func isEngagedTracksPhase() {
        var machine = HotkeyStateMachine()
        #expect(!machine.isEngaged)
        _ = machine.handle(.hotkeyDown(at: 0))
        #expect(machine.isEngaged)
        _ = machine.handle(.hotkeyUp(at: 1))
        #expect(!machine.isEngaged)
    }
}
