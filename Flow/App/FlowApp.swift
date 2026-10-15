import SwiftUI

@main
struct FlowApp: App {
    var body: some Scene {
        MenuBarExtra("Flow", systemImage: "waveform") {
            Text("Flow is starting…")
            Divider()
            Button("Quit Flow") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
