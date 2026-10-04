import AppKit
import Carbon.HIToolbox

@MainActor
final class KeyTap {
    private let switcher: Switcher
    private var tap: CFMachPort?
    private var swallowedKeyUps: Set<Int64> = []

    init(switcher: Switcher) {
        self.switcher = switcher
    }

    func install() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, context in
                let keyTap = Unmanaged<KeyTap>.fromOpaque(context!).takeUnretainedValue()
                return MainActor.assumeIsolated { keyTap.handle(type, event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable()
            return Unmanaged.passUnretained(event)
        case .keyDown:
            return keyDown(event) ? nil : Unmanaged.passUnretained(event)
        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if swallowedKeyUps.remove(code) != nil || switcher.isActive { return nil }
            return Unmanaged.passUnretained(event)
        case .flagsChanged:
            if switcher.isActive, !event.flags.contains(switcher.mode.modifier) { switcher.commit() }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func keyDown(_ event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let shift = flags.contains(.maskShift)

        if !switcher.isActive {
            guard code == kVK_Tab, !flags.contains(.maskControl) else { return false }
            let alt = flags.contains(.maskAlternate)
            let command = flags.contains(.maskCommand)
            guard alt != command else { return false }
            swallowedKeyUps.insert(code)
            switcher.begin(alt ? .workspace : .global, backward: shift)
            return true
        }

        swallowedKeyUps.insert(code)
        switch Int(code) {
        case kVK_Tab: switcher.step(shift ? -1 : 1)
        case kVK_RightArrow: switcher.step(1)
        case kVK_LeftArrow: switcher.step(-1)
        case kVK_Escape: switcher.cancel()
        case kVK_ANSI_Grave where switcher.mode == .global: switcher.jumpWorkspace(forward: !shift)
        case kVK_DownArrow where switcher.mode == .global: switcher.jumpWorkspace(forward: true)
        case kVK_UpArrow where switcher.mode == .global: switcher.jumpWorkspace(forward: false)
        case kVK_ANSI_W: switcher.closeSelected()
        case kVK_ANSI_Q: switcher.quitSelectedApp()
        default: break
        }
        return true
    }
}
