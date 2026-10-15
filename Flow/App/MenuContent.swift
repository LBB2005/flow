import SwiftUI

struct MenuContent: View {
    let app: AppModel

    var body: some View {
        Text("Hold \(app.settings.hotkey.displayName) to dictate")
        Divider()
        if !app.permissions.accessibility {
            Button("⚠︎ Allow Accessibility (needed for the hotkey)…") {
                app.permissions.promptAccessibility()
                app.permissions.openAccessibilitySettings()
            }
        }
        Divider()
        Button("Quit Flow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
