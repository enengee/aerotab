import CoreGraphics

public struct WorkspaceWindow: Equatable, Sendable {
    public let id: UInt32
    public let pid: Int32
    public let appName: String
    public let title: String
    public let layout: String
    public let workspace: String

    public init(id: UInt32, pid: Int32, appName: String, title: String, layout: String, workspace: String = "") {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.layout = layout
        self.workspace = workspace
    }

    var isAccordion: Bool { layout.hasSuffix("_accordion") }
    var isFloating: Bool { layout == "floating" }
    var isHorizontal: Bool { layout.hasPrefix("h_") }
    var isVertical: Bool { layout.hasPrefix("v_") }
}

public struct ScreenWindow: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect

    public init(id: UInt32, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public struct WindowGroup: Equatable, Sendable {
    public let workspace: String
    public let windows: [WorkspaceWindow]

    public init(workspace: String, windows: [WorkspaceWindow]) {
        self.workspace = workspace
        self.windows = windows
    }
}

public func recencyOrder(_ windows: [WorkspaceWindow], focused: UInt32?, history: [UInt32]) -> [WorkspaceWindow] {
    let rank = recencyRank(history, focused: focused)
    return windows.enumerated()
        .sorted { lhs, rhs in
            let l = rank[lhs.element.id] ?? history.count + lhs.offset
            let r = rank[rhs.element.id] ?? history.count + rhs.offset
            return l < r
        }
        .map(\.element)
}

public func workspaceGroups(
    _ windows: [WorkspaceWindow],
    focusedWorkspace: String?,
    focused: UInt32?,
    history: [UInt32]
) -> [WindowGroup] {
    var names: [String] = []
    var members: [String: [WorkspaceWindow]] = [:]
    for window in windows {
        if members[window.workspace] == nil { names.append(window.workspace) }
        members[window.workspace, default: []].append(window)
    }
    let rank = recencyRank(history, focused: focused)
    let ranked = names.enumerated().map { offset, name -> (rank: Int, group: WindowGroup) in
        let ordered = recencyOrder(members[name]!, focused: focused, history: history)
        let best = name == focusedWorkspace ? -2 : ordered.compactMap { rank[$0.id] }.min() ?? history.count + offset
        return (best, WindowGroup(workspace: name, windows: ordered))
    }
    return ranked.sorted { $0.rank < $1.rank }.map(\.group)
}

public func initialSelection(_ windows: [WorkspaceWindow], focused: UInt32?, history: [UInt32], backward: Bool) -> Int {
    guard !windows.isEmpty else { return 0 }
    if backward { return windows.count - 1 }
    let rank = recencyRank(history, focused: nil)
    let candidates = windows.indices.filter { windows[$0].id != focused }
    if let previous = candidates.min(by: { (rank[windows[$0].id] ?? .max) < (rank[windows[$1].id] ?? .max) }),
       rank[windows[previous].id] != nil {
        return previous
    }
    return candidates.first ?? 0
}

public struct Ring: Equatable, Sendable {
    public let groupSizes: [Int]

    public init(groupSizes: [Int]) {
        self.groupSizes = groupSizes.filter { $0 > 0 }
    }

    public var count: Int { groupSizes.reduce(0, +) }

    public func step(_ index: Int, by delta: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }

    public func group(of index: Int) -> Int {
        var start = 0
        for (group, size) in groupSizes.enumerated() {
            if index < start + size { return group }
            start += size
        }
        return max(groupSizes.count - 1, 0)
    }

    public func jumpWorkspace(from index: Int, forward: Bool) -> Int {
        guard !groupSizes.isEmpty else { return 0 }
        let current = group(of: index)
        let target = ((current + (forward ? 1 : -1)) % groupSizes.count + groupSizes.count) % groupSizes.count
        let start = groupSizes[..<target].reduce(0, +)
        return forward ? start : start + groupSizes[target] - 1
    }
}

private func recencyRank(_ history: [UInt32], focused: UInt32?) -> [UInt32: Int] {
    var rank: [UInt32: Int] = [:]
    for (index, id) in history.enumerated() where rank[id] == nil {
        rank[id] = index
    }
    if let focused { rank[focused] = -1 }
    return rank
}
