import Foundation

enum AppEnvironment {
    /// True when the app is hosting the unit-test bundle. Used to skip
    /// installing the event tap, opening the mic or loading models during tests.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
