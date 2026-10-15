import Testing
@testable import Flow

@MainActor
struct PillModelTests {
    @Test func levelsOnlyChangeWhenAWindowCloses() {
        let model = PillModel()
        model.push(level: 0.8, at: 0)
        model.push(level: 0.8, at: 0.05)
        #expect(model.levels.allSatisfy { $0 == 0 })
        model.push(level: 0.8, at: 0.12)
        #expect(model.levels.last! > 0)
    }

    @Test func resetZeroesLevels() {
        let model = PillModel()
        model.push(level: 0.8, at: 0)
        model.push(level: 0.8, at: 0.12)
        model.resetLevels()
        #expect(model.levels.allSatisfy { $0 == 0 })
    }
}
