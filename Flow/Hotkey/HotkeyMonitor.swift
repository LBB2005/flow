import CoreGraphics
import Foundation

/// Installs a CGEventTap and turns raw events into `HotkeyAction`s.
/// Requires Accessibility permission (it is an active tap, so it can swallow Esc and combos).
@MainActor
final class HotkeyMonitor {
    var onAction: (@MainActor (HotkeyAction) -> Void)?
    private(set) var hotkey: Hotkey

    private var machine = HotkeyStateMachine()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPaused = false
    private var tickTask: Task<Void, Never>?

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// Returns false when the tap can't be created (Accessibility not granted yet).
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("event tap creation failed (Accessibility not granted?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        Log.hotkey.notice("event tap installed for \(self.hotkey.displayName)")
        return true
    }

    func stop() {
        cancelIfEngaged()
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    /// Applies a new shortcut immediately (no restart needed).
    func setHotkey(_ newHotkey: Hotkey) {
        cancelIfEngaged()
        hotkey = newHotkey
        Log.hotkey.info("hotkey changed to \(newHotkey.displayName)")
    }

    /// Forgets a latched hands-free gesture without emitting an action (the recording already ended).
    func resetGesture() {
        machine.reset()
        tickTask?.cancel()
    }

    /// While paused every event passes straight through (used while recording a new shortcut).
    func setPaused(_ paused: Bool) {
        if paused { cancelIfEngaged() }
        isPaused = paused
    }

    // MARK: - Event handling (main thread)

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        Log.hotkey.notice("event tap re-enabled after timeout")
    }

    /// Returns true if the event should be swallowed.
    fileprivate func process(kind: KeyEventKind, keyCode: UInt16, flags: UInt64, isAutorepeat: Bool) -> Bool {
        guard !isPaused else { return false }
        let result = HotkeyEventClassifier.classify(
            hotkey: hotkey, kind: kind, keyCode: keyCode, flags: flags,
            isAutorepeat: isAutorepeat, engaged: machine.isEngaged)
        if let signal = result.signal { send(signal) }
        return result.swallow
    }

    private func send(_ signal: HotkeySignal) {
        let now = ProcessInfo.processInfo.systemUptime
        let input: HotkeyInput = switch signal {
        case .down: .hotkeyDown(at: now)
        case .up: .hotkeyUp(at: now)
        case .other: .otherInput(at: now)
        case .escape: .escape(at: now)
        }
        dispatch(machine.handle(input))
        if case .pending = machine.phase { scheduleTick() } else { tickTask?.cancel() }
    }

    private func scheduleTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HotkeyStateMachine.holdThreshold + 0.01))
            guard !Task.isCancelled, let self else { return }
            self.dispatch(self.machine.handle(.tick(at: ProcessInfo.processInfo.systemUptime)))
        }
    }

    private func cancelIfEngaged() {
        guard machine.isEngaged else { return }
        dispatch(machine.handle(.otherInput(at: ProcessInfo.processInfo.systemUptime)))
        tickTask?.cancel()
    }

    private func dispatch(_ action: HotkeyAction?) {
        guard let action else { return }
        Log.hotkey.debug("action: \(String(describing: action))")
        onAction?(action)
    }
}

/// C callback. The tap is added to the main run loop, so it always runs on the main thread.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { monitor.reenableTap() }
        return Unmanaged.passUnretained(event)
    }

    let kind: KeyEventKind
    switch type {
    case .keyDown: kind = .keyDown
    case .keyUp: kind = .keyUp
    case .flagsChanged: kind = .flagsChanged
    case .leftMouseDown, .rightMouseDown, .otherMouseDown: kind = .mouseDown
    default: return Unmanaged.passUnretained(event)
    }
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags.rawValue
    let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

    let swallow = MainActor.assumeIsolated {
        monitor.process(kind: kind, keyCode: keyCode, flags: flags, isAutorepeat: isAutorepeat)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
