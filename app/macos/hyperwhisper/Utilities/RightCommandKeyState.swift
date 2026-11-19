import CoreGraphics

/// Device-specific flags distinguish Command sides even when both keys are held.
/// The aggregate `.maskCommand` bit alone cannot identify a right-key release.
enum RightCommandKeyFlags {
    static let rightCommand = CGEventFlags(rawValue: 0x10) // NX_DEVICERCMDKEYMASK
    static let leftCommand = CGEventFlags(rawValue: 0x08) // NX_DEVICELCMDKEYMASK

    static func isPressed(_ flags: CGEventFlags) -> Bool {
        flags.contains(rightCommand)
    }

    static func hasInterference(_ flags: CGEventFlags) -> Bool {
        !flags.intersection([leftCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]).isEmpty
    }
}

/// A bare right Command press toggles once, on release. Command combinations
/// pass through normally and cannot become a toggle when their other key lifts.
struct RightCommandKeyState {
    private(set) var isPressed = false
    private(set) var isBarePress = false

    mutating func flagsChanged(_ flags: CGEventFlags) -> Bool {
        let pressed = RightCommandKeyFlags.isPressed(flags)
        let interferes = RightCommandKeyFlags.hasInterference(flags)
        defer { isPressed = pressed }

        if pressed && !isPressed {
            isBarePress = !interferes
        } else if interferes {
            isBarePress = false
        }

        guard !pressed && isPressed else { return false }
        defer { isBarePress = false }
        return isBarePress
    }

    mutating func keyDown() {
        isBarePress = false
    }
}
