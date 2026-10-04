import CoreGraphics

public struct WorkspaceWindow: Equatable, Sendable {
    public let id: UInt32
    public let pid: Int32
    public let appName: String
    public let title: String
    public let layout: String

    public init(id: UInt32, pid: Int32, appName: String, title: String, layout: String) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.layout = layout
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

public func recencyOrder(_ windows: [WorkspaceWindow], focused: UInt32?, history: [UInt32]) -> [WorkspaceWindow] {
    var rank: [UInt32: Int] = [:]
    for (index, id) in history.enumerated() where rank[id] == nil {
        rank[id] = index
    }
    if let focused { rank[focused] = -1 }
    return windows.enumerated()
        .sorted { lhs, rhs in
            let l = rank[lhs.element.id] ?? history.count + lhs.offset
            let r = rank[rhs.element.id] ?? history.count + rhs.offset
            return l < r
        }
        .map(\.element)
}
