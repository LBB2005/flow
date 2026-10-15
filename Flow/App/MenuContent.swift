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
        Divider()
        Button("Quit Flow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
