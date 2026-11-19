import AppKit

/// Toggle Recording's modifier-only input. Uses the same ordered, off-main tap
/// delivery as Push to Talk, but never uses its hold or double-press machine.
@MainActor
final class RightCommandKeyMonitor {
    static let shared = RightCommandKeyMonitor()

    fileprivate var tapThread: EventTapThread?
    private var state = RightCommandKeyState()
    var onToggle: (() -> Void)?

    func start() {
        guard tapThread == nil else { return }
        state = RightCommandKeyState()
        let thread = EventTapThread(name: "com.hyperwhisper.toggle-event-tap")
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: rightCommandToggleEventTapCallback,
            userInfo: Unmanaged.passUnretained(thread).toOpaque()
        ) else {
            AppLogger.audio.error("Right Command toggle monitor could not create an event tap; check Accessibility permission")
            return
        }
        tapThread = thread
        thread.start(tap: tap)
    }

    func stop() {
        tapThread?.stop()
        tapThread = nil
        state = RightCommandKeyState()
    }

    fileprivate enum Event {
        case flagsChanged(CGEventFlags)
        case keyDown
        case reset
    }

    fileprivate func receive(_ event: Event, from source: EventTapThread) {
        guard source === tapThread else { return }
        switch event {
        case .flagsChanged(let flags):
            if state.flagsChanged(flags) { onToggle?() }
        case .keyDown:
            state.keyDown()
        case .reset:
            // A lost release must not cause a later event to toggle recording.
            state = RightCommandKeyState()
        }
    }
}

func rightCommandToggleEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let thread = Unmanaged<EventTapThread>.fromOpaque(userInfo).takeUnretainedValue()
    let input: RightCommandKeyMonitor.Event
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        _ = thread.reEnableAfterSystemDisable(type)
        input = .reset
    case .flagsChanged:
        input = .flagsChanged(event.flags)
    case .keyDown:
        input = .keyDown
    default:
        return Unmanaged.passUnretained(event)
    }
    EventTapThread.deliverOnMainInOrder {
        RightCommandKeyMonitor.shared.receive(input, from: thread)
    }
    return Unmanaged.passUnretained(event)
}
