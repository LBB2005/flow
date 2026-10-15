import Foundation
import Testing
@testable import Flow

struct TimeoutTests {
    @Test func returnsValueWhenFast() async throws {
        let value = try await withTimeout(.seconds(1)) { 42 }
        #expect(value == 42)
    }

    @Test func throwsTimeoutWhenSlowEvenIfOperationIgnoresCancellation() async {
        let start = ContinuousClock.now
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(.milliseconds(50)) {
                // Simulates a model that never checks for cancellation.
                usleep(500_000) // blocking; Thread.sleep is unavailable in async contexts
                return 1
            }
        }
        #expect(ContinuousClock.now - start < .milliseconds(400))
    }

    @Test func propagatesOperationErrors() async {
        await #expect(throws: FakeError.self) {
            try await withTimeout(.seconds(1)) { () async throws -> Int in throw FakeError.boom }
        }
    }
}
