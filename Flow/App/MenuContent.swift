import SwiftUI

struct MenuContent: View {
    let app: AppModel

    var body: some View {
        Text(app.statusLine)
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

        Section("Models") {
            modelRow("Speech recognition", .transcriber)
            modelRow("Cleanup", .cleaner)
        }

        Divider()
        Toggle("Clean up text", isOn: Bindable(app.settings).cleanupEnabled)

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
        SettingsMenuButton()
        Divider()
        Button("Quit Flow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private func modelRow(_ title: String, _ kind: ModelManager.Kind) -> some View {
        switch app.models.status(of: kind) {
        case .checking: Text("\(title): checking…")
        case .notDownloaded: Text("\(title): not downloaded")
        case .downloading(let fraction): Text("\(title): downloading \(Int(fraction * 100))%")
        case .ready: Text("\(title): ready ✓")
        case .failed:
            Button("\(title): failed. Retry") { app.models.prepare(kind) }
        }
    }
}

/// Menu-bar apps have to activate themselves, or the Settings window opens behind other apps.
struct SettingsMenuButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
    }
}
