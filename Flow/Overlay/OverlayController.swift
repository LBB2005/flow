import AppKit
import SwiftUI

/// Borderless panel that can sit over the menu bar and notch.
final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the notch overlay. Never takes focus from the app being dictated into.
@MainActor
final class OverlayController: PillPresenter {
    let model = PillModel()
    private var panel: NotchPanel?
    private var hideTask: Task<Void, Never>?
    private var orderOutTask: Task<Void, Never>?

    func show(_ state: PillState) {
        hideTask?.cancel()
        orderOutTask?.cancel()
        if state == .listening && (model.state != .listening || !model.isExpanded) {
            model.resetLevels()
            model.recordingStartedAt = .now
        }
        let panel = self.panel ?? makePanel()
        if !model.isExpanded {
            place(panel)
            panel.orderFrontRegardless()
        }
        model.state = state
        model.isExpanded = true

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
        guard model.isExpanded else { return }
        model.isExpanded = false
        orderOutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Motion.collapseDuration + 0.05))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    func push(level: Float) {
        model.push(level: level, at: ProcessInfo.processInfo.systemUptime)
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(
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
        panel.contentView = NSHostingView(rootView: NotchView(model: model))
        self.panel = panel
        return panel
    }

    /// Always the built-in (notched) display; the main screen if it's off (lid closed).
    private func place(_ panel: NSPanel) {
        guard let screen = Self.targetScreen() else { return }
        let notch = NotchGeometry.metrics(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width)
        model.notchSize = CGSize(width: notch.width, height: notch.height)
        panel.setFrame(NotchGeometry.panelFrame(notch: notch), display: false)
    }

    static func targetScreen() -> NSScreen? {
        let builtIn = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
        return builtIn ?? NSScreen.main
    }
}
