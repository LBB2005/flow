import AppKit
import ApplicationServices
import AVFoundation
import Observation

enum PermissionStatus: Equatable, Sendable { case granted, denied, notDetermined }

@MainActor @Observable
final class PermissionsChecker {
    private(set) var microphone: PermissionStatus = .notDetermined
    private(set) var accessibility = false

    var allGranted: Bool { microphone == .granted && accessibility }

    func refresh() {
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
        accessibility = AXIsProcessTrusted()
    }

    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    /// Shows the system "Flow would like to control this computer" prompt.
    func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
