import Foundation
import Testing
@testable import Flow

@MainActor
struct SettingsStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "FlowTests.\(UUID().uuidString)")!
    }

    @Test func defaultsMatchSpec() {
        let store = SettingsStore(defaults: freshDefaults())
        #expect(store.hotkey == .modifierOnly(.rightOption))
        #expect(store.microphoneUID == nil)
        #expect(store.whisperModel == .largeV3Turbo)
        #expect(store.cleanupModel == .qwen3_1_7b)
        #expect(store.cleanupEnabled)
        #expect(store.keepWarm == .tenMinutes)
    }

    @Test func valuesPersistAcrossInstances() {
        let defaults = freshDefaults()
        let a = SettingsStore(defaults: defaults)
        a.hotkey = .combo(modifiers: .control, keyCode: KeyNames.space)
        a.microphoneUID = "BuiltInMic"
        a.whisperModel = .base
        a.cleanupModel = .qwen3_4b
        a.cleanupEnabled = false
        a.keepWarm = .always

        let b = SettingsStore(defaults: defaults)
        #expect(b.hotkey == .combo(modifiers: .control, keyCode: KeyNames.space))
        #expect(b.microphoneUID == "BuiltInMic")
        #expect(b.whisperModel == .base)
        #expect(b.cleanupModel == .qwen3_4b)
        #expect(!b.cleanupEnabled)
        #expect(b.keepWarm == .always)
    }

    @Test func corruptValuesFallBackToDefaults() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "hotkey")
        defaults.set("gpt-9", forKey: "whisperModel")
        let store = SettingsStore(defaults: defaults)
        #expect(store.hotkey == .default)
        #expect(store.whisperModel == .largeV3Turbo)
    }

    @Test func keepWarmDurations() {
        #expect(KeepWarm.twoMinutes.duration == .seconds(120))
        #expect(KeepWarm.tenMinutes.duration == .seconds(600))
        #expect(KeepWarm.thirtyMinutes.duration == .seconds(1800))
        #expect(KeepWarm.always.duration == nil)
    }
}
