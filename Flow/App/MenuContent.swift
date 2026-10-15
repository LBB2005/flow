import SwiftUI

struct MenuContent: View {
    let app: AppModel

    var body: some View {
        Text("Tap or hold \(app.settings.hotkey.displayName) to dictate")
        Divider()
        if !app.permissions.accessibility {
            Button("⚠︎ Allow Accessibility (needed for the hotkey)…") {
                app.permissions.promptAccessibility()
                app.permissions.openAccessibilitySettings()
            }
        }
        if app.permissions.microphone == .denied {
            Button("⚠︎ Allow Microphone access…") { app.permissions.openMicrophoneSettings() }
        }
        #if DEBUG
        Menu("UI Playground") {
            Button("Play all states") { app.playground.playAll() }
            Divider()
            Button("Listening") { app.playground.show(.listening) }
            Button("Thinking") { app.playground.show(.thinking) }
            Button("Pasted") { app.playground.show(.success) }
            Button("Cancelled") { app.playground.show(.cancelled) }
            Button("No speech") { app.playground.show(.noSpeech) }
            Button("Copied") { app.playground.show(.copied) }
            Button("Error") { app.playground.show(.error("Microphone access needed")) }
            Divider()
            Button("Hide") { app.playground.hide() }
        }
        #endif
        Divider()
        Button("Quit Flow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
