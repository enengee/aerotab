import AppKit
import AeroTabCore

enum SwitcherMode {
    case workspace
    case global

    var modifier: CGEventFlags { self == .workspace ? .maskAlternate : .maskCommand }
}

@MainActor
final class Switcher {
    private enum Action {
        case step(Int)
        case jump(forward: Bool)
    }

    private static let popupDelay: TimeInterval = 0.1
    private static let thumbnailPixels = CGSize(width: 800, height: 520)

    private let history: FocusHistory
    private let panel = SwitcherPanel()
    private let thumbnails = Thumbnails()

    private(set) var isActive = false
    private(set) var mode = SwitcherMode.workspace
    private var generation = 0
    private var backward = false
    private var groups: [SwitcherGroup]?
    private var snapshot: WindowSnapshot?
    private var selected = 0
    private var pending: [Action] = []
    private var commitPending = false
    private var popupDue = false
    private var icons: [Int32: CGImage] = [:]

    init(history: FocusHistory) {
        self.history = history
    }

    func begin(_ mode: SwitcherMode, backward: Bool) {
        isActive = true
        self.mode = mode
        self.backward = backward
        generation += 1
        let current = generation
        groups = nil
        snapshot = nil
        selected = 0
        pending = []
        commitPending = false
        popupDue = false

        AeroSpace.queue.async {
            let result = Result { (try AeroSpace.snapshot(allWorkspaces: mode == .global), WindowStack.onScreen()) }
            DispatchQueue.main.async { self.loaded(current, result) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.popupDelay) {
            guard current == self.generation, self.isActive else { return }
            self.popupDue = true
            self.showPanel()
        }
    }

    func step(_ delta: Int) {
        perform(.step(delta))
    }

    func jumpWorkspace(forward: Bool) {
        perform(.jump(forward: forward))
    }

    func cancel() {
        end()
    }

    func commit() {
        guard isActive else { return }
        isActive = false
        panel.hide()
        if groups == nil {
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

    private var items: [SwitcherItem] { groups?.flatMap(\.items) ?? [] }

    private var ring: Ring { Ring(groupSizes: groups?.map(\.items.count) ?? []) }

    private var selectedItem: SwitcherItem? {
        let items = items
        return items.indices.contains(selected) ? items[selected] : nil
    }

    private func perform(_ action: Action) {
        guard groups != nil else {
            pending.append(action)
            return
        }
        switch action {
        case .step(let delta): selected = ring.step(selected, by: delta)
        case .jump(let forward): selected = ring.jumpWorkspace(from: selected, forward: forward)
        }
        panel.select(selected)
    }

    private func loaded(_ current: Int, _ result: Result<(WindowSnapshot, [ScreenWindow]), Error>) {
        guard current == generation else { return }
        let snapshot: WindowSnapshot
        let stack: [ScreenWindow]
        switch result {
        case .success(let value): (snapshot, stack) = value
        case .failure(let error):
            log("snapshot: \(error)")
            return end()
        }
        guard !snapshot.windows.isEmpty else { return end() }

        let frames = Dictionary(stack.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        func item(_ window: WorkspaceWindow) -> SwitcherItem {
            let aspect = frames[window.id].map { $0.height > 0 ? $0.width / $0.height : 1.6 } ?? 1.6
            return SwitcherItem(window: window, aspect: aspect, icon: icon(for: window.pid))
        }
        let recent = history.recent
        switch mode {
        case .workspace:
            let ordered = recencyOrder(snapshot.windows, focused: snapshot.focused, history: recent)
            groups = [SwitcherGroup(label: nil, items: ordered.map(item))]
        case .global:
            groups = workspaceGroups(snapshot.windows, focusedWorkspace: snapshot.focusedWorkspace, focused: snapshot.focused, history: recent)
                .map { SwitcherGroup(label: $0.workspace, items: $0.windows.map(item)) }
        }
        self.snapshot = snapshot
        selected = initialSelection(items.map(\.window), focused: snapshot.focused, history: recent, backward: backward)
        let queued = pending
        pending = []
        queued.forEach(perform)

        if commitPending { return finishCommit() }
        if popupDue { showPanel() }
        thumbnails.capture(items.map(\.window.id), maxPixels: Self.thumbnailPixels) { [weak self] id, image in
            guard let self, current == self.generation, self.isActive else { return }
            self.panel.setThumbnail(image, for: id)
        }
    }

    private func showPanel() {
        guard isActive, let groups, !groups.isEmpty, !panel.isVisible else { return }
        panel.show(groups, selected: selected, on: targetScreen) { thumbnails.cached($0) }
    }

    private var targetScreen: NSScreen {
        let screens = NSScreen.screens
        if let index = snapshot?.screenIndex, screens.indices.contains(index - 1) { return screens[index - 1] }
        return NSScreen.main ?? screens[0]
    }

    private func finishCommit() {
        guard let item = selectedItem, let snapshot else { return end() }
        let picked = item.window
        let sameWorkspace = items.map(\.window).filter { $0.workspace == picked.workspace }
        end()
        AeroSpace.queue.async {
            do {
                if picked.workspace == snapshot.focusedWorkspace {
                    let commands = commitCommands(picked: picked.id, focused: snapshot.focused, windows: sameWorkspace, stack: WindowStack.onScreen())
                    guard !commands.isEmpty else { return }
                    NativeFocus.focus(picked.id, pid: picked.pid)
                    try AeroSpace.eval(commands)
                } else {
                    try AeroSpace.eval(["summon-workspace -- '\(picked.workspace)'", "focus --window-id \(picked.id)"])
                    NativeFocus.focus(picked.id, pid: picked.pid)
                }
            } catch {
                log("commit: \(error)")
            }
        }
    }

    private func remove(where predicate: (SwitcherItem) -> Bool) {
        guard let current = groups else { return }
        for item in current.flatMap(\.items) where predicate(item) { thumbnails.forget(item.window.id) }
        let remaining = current
            .map { SwitcherGroup(label: $0.label, items: $0.items.filter { !predicate($0) }) }
            .filter { !$0.items.isEmpty }
        groups = remaining
        if remaining.isEmpty { return end() }
        selected = min(selected, items.count - 1)
        if panel.isVisible {
            panel.hide()
            panel.show(remaining, selected: selected, on: targetScreen) { thumbnails.cached($0) }
        }
    }

    private func end() {
        isActive = false
        generation += 1
        groups = nil
        snapshot = nil
        commitPending = false
        panel.hide()
    }

    private func icon(for pid: Int32) -> CGImage? {
        if let cached = icons[pid] { return cached }
        guard let image = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
        let rendered = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        icons[pid] = rendered
        return rendered
    }
}
