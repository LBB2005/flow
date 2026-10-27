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
        #expect(store.hotkey == .combo(modifiers: .option, keyCode: KeyNames.rightArrow))
        #expect(store.microphoneUID == nil)
        #expect(store.whisperModel == .largeV3Turbo)
        #expect(store.cleanupModel == .appleIntelligence)
        #expect(store.cleanupEnabled)
        #expect(store.keepWarm == .always)
        #expect(store.transcribeWhileSpeaking)
    }

    @Test func valuesPersistAcrossInstances() {
        let defaults = freshDefaults()
        let a = SettingsStore(defaults: defaults)
        a.hotkey = .combo(modifiers: .control, keyCode: KeyNames.space)
        a.microphoneUID = "BuiltInMic"
        a.whisperModel = .base
        a.cleanupModel = .qwen3_4b
        a.cleanupEnabled = false
        a.keepWarm = .thirtyMinutes
        a.transcribeWhileSpeaking = false

        let b = SettingsStore(defaults: defaults)
        #expect(b.hotkey == .combo(modifiers: .control, keyCode: KeyNames.space))
        #expect(b.microphoneUID == "BuiltInMic")
        #expect(b.whisperModel == .base)
        #expect(b.cleanupModel == .qwen3_4b)
        #expect(!b.cleanupEnabled)
        #expect(b.keepWarm == .thirtyMinutes)
        #expect(!b.transcribeWhileSpeaking)
    }

    @Test func corruptValuesFallBackToDefaults() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "hotkey")
        defaults.set("gpt-9", forKey: "whisperModel")
        let store = SettingsStore(defaults: defaults)
        #expect(store.hotkey == .default)
        #expect(store.whisperModel == .largeV3Turbo)
    }

    /// Saved before Apple Intelligence existed, when Qwen3 1.7B was the default (spec §11 amendment 8).
    @Test func oldQwenDefaultMovesToAppleIntelligenceOnce() {
        let defaults = freshDefaults()
        defaults.set(CleanupModelChoice.qwen3_1_7b.rawValue, forKey: "cleanupModel")
        let a = SettingsStore(defaults: defaults)
        #expect(a.cleanupModel == .appleIntelligence)
        #expect(defaults.string(forKey: "cleanupModel") == CleanupModelChoice.appleIntelligence.rawValue)

        // Choosing Qwen again afterwards sticks.
        a.cleanupModel = .qwen3_1_7b
        let b = SettingsStore(defaults: defaults)
        #expect(b.cleanupModel == .qwen3_1_7b)
    }

    @Test func deliberateQwen4BChoiceIsNotMigrated() {
        let defaults = freshDefaults()
        defaults.set(CleanupModelChoice.qwen3_4b.rawValue, forKey: "cleanupModel")
        #expect(SettingsStore(defaults: defaults).cleanupModel == .qwen3_4b)
    }

    @Test func qwenChosenAfterAFreshInstallIsNotMigrated() {
        let defaults = freshDefaults()
        let a = SettingsStore(defaults: defaults)
        a.cleanupModel = .qwen3_1_7b
        #expect(SettingsStore(defaults: defaults).cleanupModel == .qwen3_1_7b)
    }

    /// Saved when 10 minutes was the default (spec §11 amendment 10).
    @Test func savedKeepWarmMovesToAlwaysOnce() {
        let defaults = freshDefaults()
        defaults.set(KeepWarm.tenMinutes.rawValue, forKey: "keepWarm")
        let a = SettingsStore(defaults: defaults)
        #expect(a.keepWarm == .always)
        #expect(defaults.string(forKey: "keepWarm") == KeepWarm.always.rawValue)

        // Choosing a shorter time afterwards sticks.
        a.keepWarm = .tenMinutes
        #expect(SettingsStore(defaults: defaults).keepWarm == .tenMinutes)
    }

    @Test func keepWarmDurations() {
        #expect(KeepWarm.twoMinutes.duration == .seconds(120))
        #expect(KeepWarm.tenMinutes.duration == .seconds(600))
        #expect(KeepWarm.thirtyMinutes.duration == .seconds(1800))
        #expect(KeepWarm.always.duration == nil)
    }
}
