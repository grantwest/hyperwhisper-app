import AppKit
import Testing
@testable import HyperWhisper

@Suite(.serialized)
struct RightCommandShortcutTests {
    private static let right: CGEventFlags = [.maskCommand, RightCommandKeyFlags.rightCommand]
    private static let left: CGEventFlags = [.maskCommand, RightCommandKeyFlags.leftCommand]

    private static func flagsEvent(_ flags: CGEventFlags, keyCode: CGKeyCode = 54) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        event.type = .flagsChanged
        event.flags = flags
        return event
    }

    @Test func rightCommandHasTheExactOptionName() {
        #expect(ToggleRecordingMode.rightCommand.localizedName == "Right Command Key")
        #expect(PushToTalkMode.rightCommand.localizedName == "Right Command Key")
        #expect(PushToTalkMode.allCases.contains(.rightCommand))
    }

    @Test func flagsDistinguishCommandSidesAndRightRelease() throws {
        #expect(RightCommandKeyFlags.isPressed(try Self.flagsEvent(Self.right).flags))
        #expect(!RightCommandKeyFlags.isPressed(try Self.flagsEvent(Self.left, keyCode: 55).flags))
        #expect(RightCommandKeyFlags.isPressed(Self.right.union(Self.left)))
        // Aggregate Command remains set after right Command lifts.
        #expect(!RightCommandKeyFlags.isPressed(Self.left))
        #expect(!RightCommandKeyFlags.isPressed(.maskCommand))
    }

    @Test func oneBarePressTogglesOnlyOnceOnRelease() throws {
        var state = RightCommandKeyState()
        let down = try Self.flagsEvent(Self.right).flags
        let up = try Self.flagsEvent([]).flags
        #expect({ !state.flagsChanged(down) }())
        #expect({ !state.flagsChanged(Self.right) }())
        #expect({ state.flagsChanged(up) }())
        #expect({ !state.flagsChanged([]) }())
        #expect({ !state.flagsChanged(Self.right) }())
        #expect({ state.flagsChanged([]) }())
    }

    @Test func leftCommandNeverToggles() {
        var state = RightCommandKeyState()
        #expect({ !state.flagsChanged(Self.left) }())
        #expect({ !state.flagsChanged([]) }())
    }

    @Test func commandCombinationsDoNotToggleOrRearm() {
        var state = RightCommandKeyState()
        #expect({ !state.flagsChanged(Self.right) }())
        state.keyDown() // For example, Command+C or Command+V.
        #expect({ !state.flagsChanged(Self.right) }())
        #expect({ !state.flagsChanged([]) }())
        #expect({ !state.flagsChanged(Self.right) }())
        #expect({ state.flagsChanged([]) }()) // The next independent bare press works.
    }

    @Test(arguments: [CGEventFlags.maskShift, .maskControl, .maskAlternate, .maskSecondaryFn, RightCommandKeyFlags.leftCommand])
    func otherModifiersCancelTheWholePress(extra: CGEventFlags) {
        var state = RightCommandKeyState()
        #expect({ !state.flagsChanged(Self.right) }())
        #expect({ !state.flagsChanged(Self.right.union(extra)) }())
        #expect({ !state.flagsChanged(Self.right) }())
        #expect(!state.isBarePress)
        #expect({ !state.flagsChanged([]) }())

        #expect({ !state.flagsChanged(Self.right.union(extra)) }())
        #expect({ !state.flagsChanged(Self.right) }())
        #expect(!state.isBarePress)
        #expect({ !state.flagsChanged([]) }())
    }

    @Test @MainActor func pushToTalkStartsOnHoldAndStopsOnRelease() async throws {
        let monitor = BareModifierKeyMonitor(mode: .rightCommand)
        defer { monitor.stop() }
        monitor.doublePressEnabled = false
        var starts = 0
        var stops = 0
        monitor.onModifierDown = { starts += 1 }
        monitor.onModifierUp = { stops += 1 }

        monitor.handleFlagsChangedEvent(try Self.flagsEvent(Self.left, keyCode: 55).flags)
        try await Task.sleep(for: .milliseconds(350))
        #expect(starts == 0)
        monitor.handleFlagsChangedEvent([])
        monitor.handleFlagsChangedEvent(try Self.flagsEvent(Self.right).flags)
        #expect(starts == 0) // Preserve the 250 ms bare-modifier activation delay.
        try await Task.sleep(for: .milliseconds(350))
        #expect(starts == 1)
        monitor.handleFlagsChangedEvent(Self.right) // Duplicate flags do not restart.
        monitor.handleFlagsChangedEvent(try Self.flagsEvent([]).flags)
        #expect(stops == 1)
        monitor.handleFlagsChangedEvent([])
        #expect(stops == 1)
    }

    @Test @MainActor func quickPushToTalkPressDoesNotRecordWhenLockIsOff() async throws {
        let monitor = BareModifierKeyMonitor(mode: .rightCommand)
        defer { monitor.stop() }
        monitor.doublePressEnabled = false
        var starts = 0
        monitor.onModifierDown = { starts += 1 }
        monitor.handleFlagsChangedEvent(Self.right)
        monitor.handleFlagsChangedEvent([])
        try await Task.sleep(for: .milliseconds(350))
        #expect(starts == 0)
    }

    @Test @MainActor func pushToTalkCommandCombinationDoesNotRecord() async throws {
        let monitor = BareModifierKeyMonitor(mode: .rightCommand)
        defer { monitor.stop() }
        monitor.doublePressEnabled = false
        var starts = 0
        monitor.onModifierDown = { starts += 1 }
        monitor.handleFlagsChangedEvent(Self.right)
        monitor.handleKeyDownEvent()
        monitor.handleFlagsChangedEvent(Self.right)
        try await Task.sleep(for: .milliseconds(350))
        monitor.handleFlagsChangedEvent([])
        #expect(starts == 0)
    }

    @Test @MainActor func releasingRightCommandWithLeftHeldCannotLeavePushToTalkActive() async throws {
        let monitor = BareModifierKeyMonitor(mode: .rightCommand)
        defer { monitor.stop() }
        monitor.doublePressEnabled = false
        var starts = 0
        var cancellations = 0
        monitor.onModifierDown = { starts += 1 }
        monitor.onInterferenceDetected = { cancellations += 1 }
        monitor.handleFlagsChangedEvent(Self.right)
        try await Task.sleep(for: .milliseconds(350))
        #expect(starts == 1)
        monitor.handleFlagsChangedEvent(Self.right.union(Self.left))
        #expect(cancellations == 1)
        monitor.handleFlagsChangedEvent(Self.left)
        monitor.handleFlagsChangedEvent([])
        try await Task.sleep(for: .milliseconds(350))
        #expect(starts == 1)
        #expect(cancellations == 1)
    }

    @Test(arguments: [CGEventFlags.maskShift, .maskControl, .maskAlternate, RightCommandKeyFlags.leftCommand])
    @MainActor func pushToTalkDoesNotStartInAnExistingModifierCombination(extra: CGEventFlags) async throws {
        let monitor = BareModifierKeyMonitor(mode: .rightCommand)
        defer { monitor.stop() }
        monitor.doublePressEnabled = false
        var starts = 0
        monitor.onModifierDown = { starts += 1 }
        monitor.handleFlagsChangedEvent(Self.right.union(extra))
        monitor.handleFlagsChangedEvent(Self.right)
        try await Task.sleep(for: .milliseconds(350))
        monitor.handleFlagsChangedEvent([])
        #expect(starts == 0)
    }

    @Test(arguments: [BareModifierKeyMonitor.ModifierKey.control, .leftOption, .rightOption])
    @MainActor func existingBareModifierHoldAndReleaseStillWork(mode: BareModifierKeyMonitor.ModifierKey) async throws {
        let monitor = BareModifierKeyMonitor(mode: mode)
        defer { monitor.stop() }
        monitor.doublePressEnabled = false
        let flags: CGEventFlags
        switch mode {
        case .control: flags = .maskControl
        case .leftOption: flags = [.maskAlternate, CGEventFlags(rawValue: 0x20)]
        default: flags = [.maskAlternate, CGEventFlags(rawValue: 0x40)]
        }
        var starts = 0
        var stops = 0
        monitor.onModifierDown = { starts += 1 }
        monitor.onModifierUp = { stops += 1 }
        monitor.handleFlagsChangedEvent(flags)
        try await Task.sleep(for: .milliseconds(350))
        #expect(starts == 1)
        monitor.handleFlagsChangedEvent([])
        #expect(stops == 1)
    }

    @Test @MainActor func commandCombinationsCannotUnlockADoublePressLockedRecording() async throws {
        let monitor = BareModifierKeyMonitor(mode: .rightCommand)
        defer { monitor.stop() }
        monitor.doublePressEnabled = true
        var starts = 0
        var stops = 0
        monitor.onModifierDown = { starts += 1 }
        monitor.onModifierUp = { stops += 1 }
        for _ in 0..<2 {
            monitor.handleFlagsChangedEvent(Self.right)
            monitor.handleFlagsChangedEvent([])
        }
        try await Task.sleep(for: .milliseconds(1_150))
        #expect(starts == 1)
        #expect(stops == 0)
        for _ in 0..<2 {
            monitor.handleFlagsChangedEvent(Self.right)
            monitor.handleKeyDownEvent() // Command+C, then Command+V.
            monitor.handleFlagsChangedEvent([])
        }
        #expect(stops == 0)
        for _ in 0..<2 {
            monitor.handleFlagsChangedEvent(Self.right)
            monitor.handleFlagsChangedEvent([])
        }
        #expect(stops == 1) // Two bare presses still unlock.
    }

    @Test @MainActor func aHoldStillStopsWithDoublePressEnabled() async throws {
        let monitor = BareModifierKeyMonitor(mode: .rightCommand)
        defer { monitor.stop() }
        monitor.doublePressEnabled = true
        var starts = 0
        var stops = 0
        monitor.onModifierDown = { starts += 1 }
        monitor.onModifierUp = { stops += 1 }
        monitor.handleFlagsChangedEvent(Self.right)
        try await Task.sleep(for: .milliseconds(350))
        #expect(starts == 1)
        monitor.handleFlagsChangedEvent([])
        #expect(stops == 1)
    }

    @Test func onlyImportedDuplicateRightCommandBindingsAreSuppressed() {
        for mode in PushToTalkMode.allCases {
            #expect(mode.effectiveMode(toggleRecordingMode: .custom) == mode)
            #expect(mode.effectiveMode(toggleRecordingMode: .rightCommand) == (mode == .rightCommand ? .disabled : mode))
        }
    }

    @Test func aModeChangeKeepsTheCustomToggleAvailableUntilRecordingEnds() {
        var configuration = RecordingShortcutConfiguration()
        let appliedDuringRecording = configuration.update(toggleMode: .rightCommand, pushToTalkMode: .disabled, isRecording: true)
        #expect(!appliedDuringRecording)
        #expect(configuration.toggleMode == .custom) // Both registration and callbacks use this mode.
        let appliedAfterRecording = configuration.update(toggleMode: .rightCommand, pushToTalkMode: .disabled, isRecording: false)
        #expect(appliedAfterRecording)
        #expect(configuration.toggleMode == .rightCommand)
    }

    @Test func aModeChangeKeepsTheCustomPushToTalkReleaseAvailable() {
        var configuration = RecordingShortcutConfiguration()
        let initial = configuration.update(toggleMode: .custom, pushToTalkMode: .custom, isRecording: false)
        #expect(initial)
        let deferred = configuration.update(toggleMode: .rightCommand, pushToTalkMode: .rightCommand, isRecording: true)
        #expect(!deferred)
        #expect(configuration.toggleMode == .custom)
        #expect(configuration.pushToTalkMode == .custom) // The held shortcut's release still stops recording.
        let applied = configuration.update(toggleMode: .rightCommand, pushToTalkMode: .rightCommand, isRecording: false)
        #expect(applied)
        #expect(configuration.toggleMode == .rightCommand)
        #expect(configuration.pushToTalkMode == .disabled) // Imported duplicates have 1 owner.
    }

    @Test func returningToCustomChecksTheSavedComboAgainstLiveActions() {
        let combo = "saved-combo"
        #expect(ShortcutConflictGuard.conflictingAction(
            for: combo, recording: "toggleRecordingWithTranscription", bindings: [
                ("changeMode", combo), ("cancelRecording", "escape"),
            ]
        ) == "changeMode")
    }

    @Test func deferredRecordingInputsStillBlockConflictingCustomCombos() {
        var applied = RecordingShortcutConfiguration()
        let initial = applied.update(toggleMode: .custom, pushToTalkMode: .custom, isRecording: false)
        #expect(initial)
        let actions = ShortcutConflictGuard.liveActions(
            toggleRecordingMode: .rightCommand, pushToTalkMode: .rightCommand,
            quickCaptureEnabled: false, streamingEnabled: false, appliedConfiguration: applied
        )
        #expect(actions.contains(.toggleRecordingWithTranscription))
        #expect(actions.contains(.pushToTalk))
        #expect(Set(actions).count == actions.count)
    }

    @Test func rightCommandCannotBelongToBothActions() {
        #expect(ShortcutConflictGuard.rightCommandConflict(
            recording: .toggleRecordingWithTranscription, toggleRecordingMode: .custom, pushToTalkMode: .rightCommand
        ) == .pushToTalk)
        #expect(ShortcutConflictGuard.rightCommandConflict(
            recording: .pushToTalk, toggleRecordingMode: .rightCommand, pushToTalkMode: .fn
        ) == .toggleRecordingWithTranscription)
        #expect(ShortcutConflictGuard.rightCommandConflict(
            recording: .pushToTalk, toggleRecordingMode: .custom, pushToTalkMode: .rightCommand
        ) == nil)
        #expect(!ShortcutConflictGuard.liveActions(
            toggleRecordingMode: .rightCommand, pushToTalkMode: .rightCommand,
            quickCaptureEnabled: false, streamingEnabled: false
        ).contains(.toggleRecordingWithTranscription))
    }
}
