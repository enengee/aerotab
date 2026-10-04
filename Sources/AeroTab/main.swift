import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyTap: KeyTap?
    private var history: FocusHistory?
    private var signalSources: [DispatchSourceSignal] = []

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

        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                NativeCommandTab.setEnabled(true)
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NativeCommandTab.setEnabled(true)
    }

    private func installTap(_ keyTap: KeyTap) {
        if keyTap.install() {
            NativeCommandTab.setEnabled(false)
            return
        }
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
