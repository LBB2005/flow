import SwiftUI

@main
struct FlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(app: appDelegate.model)
        } label: {
            Image(systemName: appDelegate.model.menuBarSymbol)
        }
    }
}
