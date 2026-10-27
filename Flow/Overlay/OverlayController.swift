import AppKit
import SwiftUI

/// Borderless panel for the floating pill. Never becomes key, so the target app keeps focus.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the floating pill above the Dock. Never takes focus from the app being dictated into.
@MainActor
final class OverlayController: PillPresenter {
    let model = PillModel()
    private var panel: PillPanel?
    private var hideTask: Task<Void, Never>?
    private var orderOutTask: Task<Void, Never>?

    func show(_ state: PillState) {
        hideTask?.cancel()
        orderOutTask?.cancel()
        if state == .listening && (model.state != .listening || !model.isVisible) {
            model.resetLevels()
            model.recordingStartedAt = .now
        }
        let panel = self.panel ?? makePanel()
        if !model.isVisible {
            // Re-placed on every appearance so it follows the user to whichever screen they're on.
            place(panel)
            panel.orderFrontRegardless()
        }
        model.state = state
        model.isVisible = true

        if let delay = state.autoHideAfter {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        guard model.isVisible else { return }
        model.isVisible = false
        orderOutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Motion.disappearDuration + 0.05))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    func push(level: Float) {
        model.push(level: level, at: ProcessInfo.processInfo.systemUptime)
    }

    private func makePanel() -> PillPanel {
        let panel = PillPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: PillView(model: model))
        self.panel = panel
        return panel
    }

    /// Bottom-centre of the screen under the mouse, 16 pt above the Dock.
    private func place(_ panel: NSPanel) {
        guard let screen = Self.targetScreen() else { return }
        panel.setFrame(PillGeometry.panelFrame(visibleFrame: screen.visibleFrame), display: false)
    }

    static func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let fallback = NSScreen.main.flatMap { main in screens.firstIndex(of: main) }
        guard let index = PillGeometry.screenIndex(mouse: NSEvent.mouseLocation,
                                                   screenFrames: screens.map(\.frame),
                                                   fallback: fallback) else { return nil }
        return screens[index]
    }
}
