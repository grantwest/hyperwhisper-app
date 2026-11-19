//
//  BackupRightCommandShortcutTests.swift
//  hyperwhisperTests
//
//  Backup DTO and shared-adapter coverage. These tests do not change live settings.
//

import Foundation
import Testing
@testable import HyperWhisper

struct BackupRightCommandShortcutTests {
    private static let savedCombo = BackupShortcutBinding.combo(carbonKeyCode: 32, carbonModifiers: 4608)

    private static func shortcuts(toggle: String? = nil, pushToTalk: String = "disabled") -> BackupShortcutSettings {
        BackupShortcutSettings(
            pushToTalkMode: pushToTalk,
            pushToTalkDoublePressEnabled: false,
            quickCaptureEnabled: nil,
            quickCaptureModeId: nil,
            keyboardShortcuts: ["toggleRecordingWithTranscription": savedCombo],
            toggleRecordingMode: toggle
        )
    }

    @Test(arguments: ["custom", "rightCommand"])
    func toggleModeAndSavedComboRoundTripThroughV1(_ mode: String) throws {
        let exported = Self.shortcuts(toggle: mode, pushToTalk: "rightCommand")
        let data = try JSONEncoder().encode(exported)
        let imported = try JSONDecoder().decode(BackupShortcutSettings.self, from: data)
        #expect(imported.toggleRecordingMode == mode)
        #expect(imported.pushToTalkMode == "rightCommand")
        #expect(imported.keyboardShortcuts == exported.keyboardShortcuts)
        #expect(ToggleRecordingMode(rawValue: mode) != nil)
        #expect(PushToTalkMode(rawValue: imported.pushToTalkMode) == .rightCommand)
    }

    @Test func oldAndNullFieldsDecodeWithoutSelectingAToggleMode() throws {
        for json in [
            #"{"pushToTalkMode":"disabled","pushToTalkDoublePressEnabled":false}"#,
            #"{"pushToTalkMode":"disabled","pushToTalkDoublePressEnabled":false,"toggleRecordingMode":null}"#,
        ] {
            let imported = try JSONDecoder().decode(BackupShortcutSettings.self, from: Data(json.utf8))
            #expect(imported.toggleRecordingMode == nil)
        }
        // Existing memberwise initializer calls can omit the new argument.
        let legacy = BackupShortcutSettings(
            pushToTalkMode: "disabled", pushToTalkDoublePressEnabled: false,
            quickCaptureEnabled: nil, quickCaptureModeId: nil
        )
        let data = try JSONEncoder().encode(legacy)
        let wire = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(wire["toggleRecordingMode"] == nil)
    }

    @Test func anUnknownModeDoesNotPreventDecodingOtherShortcutFields() throws {
        let exported = Self.shortcuts(toggle: "futureMode", pushToTalk: "rightCommand")
        let data = try JSONEncoder().encode(exported)
        let imported = try JSONDecoder().decode(BackupShortcutSettings.self, from: data)
        let rawMode = try #require(imported.toggleRecordingMode)
        #expect(ToggleRecordingMode(rawValue: rawMode) == nil)
        #expect(imported.pushToTalkMode == "rightCommand")
        #expect(imported.keyboardShortcuts == exported.keyboardShortcuts)
    }

    @Test(arguments: ["custom", "rightCommand"])
    func bothModesAndTheSavedComboSurviveTheUniversalAdapter(_ mode: String) throws {
        let exported = Self.shortcuts(toggle: mode, pushToTalk: "rightCommand")
        let shortcuts = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(exported))
        let macosData = try JSONEncoder().encode(JSONValue.object(["shortcuts": shortcuts]))
        let record = try macosSettingsToUniversalSettingsJson(
            macosJson: String(decoding: macosData, as: UTF8.self), existingMacosExtJson: nil
        )
        let recordValue = try JSONDecoder().decode(JSONValue.self, from: Data(record.utf8))
        let extensionShortcuts = recordValue.objectValue?["platformExtensions"]?
            .objectValue?["macos"]?.objectValue?["settings"]?.objectValue?["shortcuts"]
        #expect(extensionShortcuts?.objectValue?["toggleRecordingMode"]?.stringValue == mode)

        let back = try universalSettingsToMacosSettingsJson(recordJson: record)
        let backValue = try JSONDecoder().decode(JSONValue.self, from: Data(back.utf8))
        let restored = try #require(backValue.objectValue?["shortcuts"])
        let imported = try JSONDecoder().decode(
            BackupShortcutSettings.self, from: JSONEncoder().encode(restored)
        )
        #expect(imported.toggleRecordingMode == mode)
        #expect(imported.pushToTalkMode == "rightCommand")
        #expect(imported.keyboardShortcuts == exported.keyboardShortcuts)
    }

    @Test func aV2BackupWithoutTheFieldKeepsTheBaselineToggleMode() throws {
        let baseline = try Self.baseline()
        for extensions: JSONValue? in [nil, .object([
            "macos": .object(["settings": .object([
                "shortcuts": .object(["pushToTalkMode": .string("rightCommand")]),
            ])]),
        ])] {
            let imported = try BackupManager.macosSettings(
                fromV2: .object([:]), platformExtensions: extensions, baseline: baseline
            )
            #expect(imported.shortcuts.toggleRecordingMode == "rightCommand")
            #expect(imported.shortcuts.keyboardShortcuts == baseline.shortcuts.keyboardShortcuts)
        }
    }

    private static func baseline() throws -> BackupSettings {
        let json = #"""
        {
          "general": {
            "launchAtLogin": false, "showInDock": true, "launchMinimized": false,
            "showRecordingWindow": true, "checkForUpdatesAutomatically": true, "enableErrorLogging": false
          },
          "audio": {
            "autoIncreaseMicVolume": false, "mediaControlMode": "off",
            "enableSoundEffects": false, "soundTheme": "default", "soundEffectsVolume": 0.5
          },
          "storage": {"filesyncEnabled": false, "storeAsM4A": true},
          "textOutput": {
            "pasteResultText": true, "restoreClipboardAfterPaste": true, "clipboardRestoreDelaySeconds": 1
          },
          "shortcuts": {
            "pushToTalkMode": "disabled", "pushToTalkDoublePressEnabled": false,
            "toggleRecordingMode": "rightCommand",
            "keyboardShortcuts": {"toggleRecordingWithTranscription": {"carbonKeyCode":32,"carbonModifiers":4608}}
          },
          "aiModel": {
            "showExperimentalModels": false, "defaultTranscriptionModel": "base", "defaultLanguage": "en",
            "defaultModelByMode": {}
          },
          "advanced": {"maxRecordingDuration": 3600, "audioSampleRate": 16000, "keepAudioFiles": true, "historyRetentionDays": 30}
        }
        """#
        return try JSONDecoder().decode(BackupSettings.self, from: Data(json.utf8))
    }
}
