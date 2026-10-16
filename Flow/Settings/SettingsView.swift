import SwiftUI

/// Layout A from `docs/mockups/settings-decision.md`: one grouped form.
struct SettingsView: View {
    let app: AppModel
    @State private var microphones: [AudioInputDevice] = []
    @State private var shortcutRejection: String?
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("Shortcut") {
                LabeledContent {
                    HotkeyRecorderView(hotkey: $settings.hotkey, rejection: $shortcutRejection) { recording in
                        app.hotkeyMonitor.setPaused(recording)
                    }
                } label: {
                    Text("Dictate")
                    Text("Tap to start and stop · hold to talk · Esc cancels")
                }
                if let shortcutRejection {
                    Text(shortcutRejection).font(.callout).foregroundStyle(.red)
                } else if case .warning(let warning) = settings.hotkey.validation {
                    Text(warning).font(.callout).foregroundStyle(.orange)
                }
            }

            Section("Microphone") {
                Picker("Input", selection: $settings.microphoneUID) {
                    Text("System default").tag(String?.none)
                    ForEach(microphones) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                    if let uid = settings.microphoneUID, !microphones.contains(where: { $0.uid == uid }) {
                        Text("Disconnected microphone").tag(Optional(uid))
                    }
                }
            }

            Section("Models") {
                modelPicker("Speech recognition", .transcriber, selection: $settings.whisperModel)
                modelPicker("Cleanup model", .cleaner, selection: $settings.cleanupModel)
                Toggle(isOn: $settings.cleanupEnabled) {
                    Text("Clean up text")
                    Text("Removes ums and repeats, fixes punctuation. Off pastes the raw transcript.")
                }
                Picker(selection: $settings.keepWarm) {
                    ForEach(KeepWarm.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("Keep models loaded for")
                    Text("Longer = instant dictation; shorter frees about 2 GB of memory sooner.")
                }
            }

            Section("Permissions") {
                permissionRow(granted: app.permissions.microphone == .granted, open: openMicrophoneAccess) {
                    Text("Microphone")
                }
                permissionRow(granted: app.permissions.accessibility, open: app.permissions.openAccessibilitySettings) {
                    Text("Accessibility")
                    Text("Lets Flow see the shortcut in any app and paste for you.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .onAppear(perform: refresh)
        // Coming back from System Settings (or plugging in a mic): show the current state.
        .onChange(of: controlActiveState) { _, state in
            if state == .key { refresh() }
        }
        .onChange(of: settings.hotkey) { _, newHotkey in app.hotkeyMonitor.setHotkey(newHotkey) }
        .onChange(of: settings.microphoneUID) { _, uid in app.recorder.preferredDeviceUID = uid }
        .onChange(of: settings.whisperModel) { app.switchWhisperModel() }
        .onChange(of: settings.cleanupModel) { app.switchCleanupModel() }
        .onChange(of: settings.keepWarm) { app.models.touch() }
    }

    private func refresh() {
        microphones = AudioDevices.inputDevices()
        app.permissions.refresh()
    }

    private func openMicrophoneAccess() {
        if app.permissions.microphone == .notDetermined {
            Task { await app.permissions.requestMicrophone() }
        } else {
            app.permissions.openMicrophoneSettings()
        }
    }

    // MARK: - Rows

    private func modelPicker<Choice: Hashable & Identifiable & CaseIterable>(
        _ title: String, _ kind: ModelManager.Kind, selection: Binding<Choice>
    ) -> some View where Choice.AllCases: RandomAccessCollection, Choice: ModelChoiceLabel {
        LabeledContent {
            Picker(title, selection: selection) {
                ForEach(Choice.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        } label: {
            Text(title)
            modelStatus(kind)
        }
    }

    @ViewBuilder
    private func modelStatus(_ kind: ModelManager.Kind) -> some View {
        switch app.models.status(of: kind) {
        case .ready:
            Text("Ready ✓").foregroundStyle(.green)
        case .downloading(let fraction):
            Text("Downloading… \(Int(fraction * 100))%").foregroundStyle(.orange)
        case .checking:
            Text("Checking…").foregroundStyle(.secondary)
        case .notDownloaded:
            Text("Not downloaded").foregroundStyle(.secondary)
        case .failed(let reason):
            HStack(spacing: 6) {
                Text("Download failed").foregroundStyle(.red).help(reason)
                Button("Retry") { app.models.prepare(kind) }
                    .controlSize(.small)
            }
        }
    }

    private func permissionRow<Label: View>(
        granted: Bool, open: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label
    ) -> some View {
        LabeledContent {
            if granted {
                SwiftUI.Label("Allowed", systemImage: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings", action: open)
            }
        } label: {
            label()
        }
    }
}

/// Lets one picker helper serve both model choice enums.
protocol ModelChoiceLabel {
    var label: String { get }
}

extension WhisperModelChoice: ModelChoiceLabel {}
extension CleanupModelChoice: ModelChoiceLabel {}

#Preview {
    SettingsView(app: AppModel())
}
