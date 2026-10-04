import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyTap: KeyTap?
    private var history: FocusHistory?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let history = FocusHistory(seed: WindowStack.onScreen().map(\.id))
        history.start()
        self.history = history

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }

        let keyTap = KeyTap(switcher: Switcher(history: history))
        self.keyTap = keyTap
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(prompt) { log("waiting for Accessibility permission") }
        installTap(keyTap)

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { keyTap.reenable() }
        }
    }

    private func installTap(_ keyTap: KeyTap) {
        if keyTap.install() { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.installTap(keyTap) }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
