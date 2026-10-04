import AppKit
import AeroTabCore

@MainActor
final class Switcher {
    private static let popupDelay: TimeInterval = 0.1
    private static let thumbnailPixels = CGSize(width: 800, height: 520)

    private let history: FocusHistory
    private let panel = SwitcherPanel()
    private let thumbnails = Thumbnails()

    private(set) var isActive = false
    private var generation = 0
    private var items: [SwitcherItem]?
    private var focused: UInt32?
    private var screenIndex: Int?
    private var selected = 0
    private var pendingSteps = 0
    private var commitPending = false
    private var popupDue = false
    private var icons: [Int32: CGImage] = [:]

    init(history: FocusHistory) {
        self.history = history
    }

    private func icon(for pid: Int32) -> CGImage? {
        if let cached = icons[pid] { return cached }
        guard let image = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
        let rendered = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        icons[pid] = rendered
        return rendered
    }

    func begin(backward: Bool) {
        isActive = true
        generation += 1
        let current = generation
        items = nil
        focused = nil
        selected = 0
        pendingSteps = backward ? -1 : 1
        commitPending = false
        popupDue = false

        AeroSpace.queue.async {
            let result = Result { (try AeroSpace.snapshot(), WindowStack.onScreen()) }
            DispatchQueue.main.async { self.loaded(current, result) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.popupDelay) {
            guard current == self.generation, self.isActive else { return }
            self.popupDue = true
            self.showPanel()
        }
    }

    func step(_ delta: Int) {
        guard let items else {
            pendingSteps += delta
            return
        }
        selected = Self.wrap(selected + delta, items.count)
        panel.select(selected)
    }

    func cancel() {
        end()
    }

    func commit() {
        guard isActive else { return }
        isActive = false
        panel.hide()
        if items == nil {
            commitPending = true
        } else {
            finishCommit()
        }
    }

    func closeSelected() {
        guard let item = selectedItem else { return }
        let id = item.window.id
        AeroSpace.queue.async {
            do { try AeroSpace.eval(["close --window-id \(id)"]) } catch { log("close: \(error)") }
        }
        remove { $0.window.id == id }
    }

    func quitSelectedApp() {
        guard let item = selectedItem else { return }
        let pid = item.window.pid
        NSRunningApplication(processIdentifier: pid)?.terminate()
        remove { $0.window.pid == pid }
    }

    private var selectedItem: SwitcherItem? {
        guard let items, items.indices.contains(selected) else { return nil }
        return items[selected]
    }

    private func loaded(_ current: Int, _ result: Result<(WorkspaceSnapshot, [ScreenWindow]), Error>) {
        guard current == generation else { return }
        let snapshot: WorkspaceSnapshot
        let stack: [ScreenWindow]
        switch result {
        case .success(let value): (snapshot, stack) = value
        case .failure(let error):
            log("snapshot: \(error)")
            end()
            return
        }
        guard !snapshot.windows.isEmpty else {
            end()
            return
        }

        let frames = Dictionary(stack.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        let ordered = recencyOrder(snapshot.windows, focused: snapshot.focused, history: history.recent)
        items = ordered.map { window in
            let frame = frames[window.id]
            let aspect = frame.map { $0.height > 0 ? $0.width / $0.height : 1.6 } ?? 1.6
            return SwitcherItem(window: window, aspect: aspect, icon: icon(for: window.pid))
        }
        focused = snapshot.focused
        screenIndex = snapshot.screenIndex
        selected = Self.wrap(pendingSteps, ordered.count)

        if commitPending {
            finishCommit()
            return
        }
        if popupDue { showPanel() }
        thumbnails.capture(ordered.map(\.id), maxPixels: Self.thumbnailPixels) { [weak self] id, image in
            guard let self, current == self.generation, self.isActive else { return }
            self.panel.setThumbnail(image, for: id)
        }
    }

    private func showPanel() {
        guard isActive, let items, !items.isEmpty, !panel.isVisible else { return }
        panel.show(items, selected: selected, on: targetScreen) { thumbnails.cached($0) }
    }

    private var targetScreen: NSScreen {
        let screens = NSScreen.screens
        if let screenIndex, screens.indices.contains(screenIndex - 1) { return screens[screenIndex - 1] }
        return NSScreen.main ?? screens[0]
    }

    private func finishCommit() {
        guard let item = selectedItem else { return end() }
        let picked = item.window.id
        let pid = item.window.pid
        let focused = focused
        let windows = items?.map(\.window) ?? []
        end()
        AeroSpace.queue.async {
            let commands = commitCommands(picked: picked, focused: focused, windows: windows, stack: WindowStack.onScreen())
            guard !commands.isEmpty else { return }
            NativeFocus.focus(picked, pid: pid)
            do { try AeroSpace.eval(commands) } catch { log("commit: \(error)") }
        }
    }

    private func remove(where predicate: (SwitcherItem) -> Bool) {
        guard var items else { return }
        for id in items.filter(predicate).map(\.window.id) { thumbnails.forget(id) }
        items.removeAll(where: predicate)
        self.items = items
        if items.isEmpty { return end() }
        selected = min(selected, items.count - 1)
        if panel.isVisible {
            panel.hide()
            panel.show(items, selected: selected, on: targetScreen) { thumbnails.cached($0) }
        }
    }

    private func end() {
        isActive = false
        generation += 1
        items = nil
        commitPending = false
        panel.hide()
    }

    private static func wrap(_ value: Int, _ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((value % count) + count) % count
    }
}
