import Foundation

/// Requested settings do not replace a recording's input until it finishes.
/// Registration and callbacks use this same applied configuration, so a mode
/// change cannot remove the toggle or release event that stops the recording.
struct RecordingShortcutConfiguration: Equatable {
    private(set) var toggleMode: ToggleRecordingMode = .custom
    private(set) var pushToTalkMode: PushToTalkMode = .disabled

    mutating func update(toggleMode: ToggleRecordingMode, pushToTalkMode: PushToTalkMode, isRecording: Bool) -> Bool {
        guard !isRecording else { return false }
        self.toggleMode = toggleMode
        self.pushToTalkMode = pushToTalkMode.effectiveMode(toggleRecordingMode: toggleMode)
        return true
    }
}

extension Notification.Name {
    static let recordingShortcutConfigurationDidChange = Notification.Name("recordingShortcutConfigurationDidChange")
}
