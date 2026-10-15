import Testing
@testable import Flow

struct SmokeTests {
    @Test func detectsThatTestsAreRunning() {
        #expect(AppEnvironment.isRunningTests)
    }
}
