import AppKit
import SwiftUI

/// Click, press a key or combo, done. Pauses the global hotkey while recording
/// so pressing the current hotkey here doesn't start a dictation.
/// The rejection message is a binding so the form can show it in its own row under the shortcut.
struct HotkeyRecorderView: View {
    @Binding var hotkey: Hotkey
    @Binding var rejection: String?
    var onRecordingChanged: (Bool) -> Void

    @State private var isRecording = false
    @State private var capture = ShortcutCapture()
    @State private var monitor: Any?
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        HStack(spacing: 8) {
            recorderButton
            Button("Reset") {
                stopRecording()
                hotkey = .default
                rejection = nil
            }
            .disabled(hotkey == .default && !isRecording && rejection == nil)
        }
        .onDisappear { stopRecording() }
        // Key events only reach this window while it's key; stop rather than leave the hotkey paused.
        .onChange(of: controlActiveState) { _, state in
            if state != .key { stopRecording() }
        }
    }

    @ViewBuilder
    private var recorderButton: some View {
        let button = Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Press a key or shortcut…" : hotkey.displayName)
                .fontWeight(.semibold)
                .frame(minWidth: 160)
        }
        .accessibilityLabel("Dictation shortcut")
        .accessibilityValue(isRecording ? "Recording. Press a key or shortcut." : hotkey.displayName)
        .accessibilityHint("Click, then press a key or shortcut.")
        if isRecording {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func startRecording() {
        capture = ShortcutCapture()
        rejection = nil
        isRecording = true
        onRecordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Pull out Sendable values before hopping onto the main actor.
            let keyCode = event.keyCode
            let flags = UInt64(event.modifierFlags.rawValue)
            let isKeyDown = event.type == .keyDown
            MainActor.assumeIsolated {
                let result = isKeyDown
                    ? capture.handleKeyDown(keyCode: keyCode, flags: flags)
                    : capture.handleFlagsChanged(keyCode: keyCode, flags: flags)
                if let result { finish(result) }
            }
            return nil // swallow everything while recording
        }
    }

    private func finish(_ result: ShortcutCapture.Result) {
        switch result {
        case .captured(let newHotkey):
            hotkey = newHotkey
            rejection = nil
            stopRecording()
        case .cancelled:
            stopRecording()
        case .rejected(let reason):
            rejection = reason
            capture = ShortcutCapture() // keep listening for another try
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { onRecordingChanged(false) }
        isRecording = false
    }
}
