import CoreGraphics
import Foundation

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> CGError

enum NativeCommandTab {
    private static let commandTab: Int32 = 1
    private static let commandShiftTab: Int32 = 2

    static func setEnabled(_ enabled: Bool) {
        _ = CGSSetSymbolicHotKeyEnabled(commandTab, enabled)
        _ = CGSSetSymbolicHotKeyEnabled(commandShiftTab, enabled)
    }
}
