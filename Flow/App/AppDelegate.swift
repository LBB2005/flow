import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.pipeline.notice("launched; running tests: \(AppEnvironment.isRunningTests)")
        model.start()
    }
}
