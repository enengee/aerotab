import ApplicationServices
import CoreGraphics

@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ windowId: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
private func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

@_silgen_name("GetProcessForPID")
private func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>) -> AXError

enum NativeFocus {
    private static let userGenerated: UInt32 = 0x200

    static func focus(_ windowId: UInt32, pid: Int32) {
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == noErr else { return }
        _ = _SLPSSetFrontProcessWithOptions(&psn, windowId, userGenerated)
        makeKey(&psn, windowId)
        if let window = axWindow(windowId, pid: pid) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    private static func makeKey(_ psn: inout ProcessSerialNumber, _ windowId: UInt32) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowId) { id in
            for index in 0..<4 { bytes[0x3c + index] = id[index] }
        }
        for index in 0x20..<0x30 { bytes[index] = 0xff }
        bytes[0x08] = 0x01
        _ = SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = SLPSPostEventRecordTo(&psn, &bytes)
    }

    private static func axWindow(_ windowId: UInt32, pid: Int32) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }
        return windows.first { window in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(window, &id) == .success && id == windowId
        }
    }
}
