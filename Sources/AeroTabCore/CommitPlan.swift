import CoreGraphics

public enum Direction: String, Sendable {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
}

public let visibleThreshold = 0.5

public func commitCommands(
    picked: UInt32,
    focused: UInt32?,
    windows: [WorkspaceWindow],
    stack: [ScreenWindow]
) -> [String] {
    if picked == focused { return [] }
    let focus = "focus --window-id \(picked)"

    guard let pickedFrame = frame(of: picked, in: stack) else { return [focus] }
    if visibleFraction(of: picked, in: stack) >= visibleThreshold { return [focus] }

    guard let focused,
          let focusedFrame = frame(of: focused, in: stack),
          let pickedWindow = windows.first(where: { $0.id == picked }),
          let focusedWindow = windows.first(where: { $0.id == focused }),
          pickedWindow.isAccordion,
          pickedWindow.layout == focusedWindow.layout,
          overlapRatio(pickedFrame, focusedFrame) >= 0.5
    else { return [focus] }

    let focusedCenter = center(focusedFrame)
    let slots: [(window: WorkspaceWindow, frame: CGRect)] = windows.compactMap { window in
        guard window.id != picked, window.id != focused, !window.isFloating,
              let windowFrame = frame(of: window.id, in: stack),
              visibleFraction(of: window.id, in: stack) >= visibleThreshold,
              overlapRatio(windowFrame, focusedFrame) < 0.5
        else { return nil }
        return (window, windowFrame)
    }
    guard let target = slots.min(by: { distance(center($0.frame), focusedCenter) < distance(center($1.frame), focusedCenter) })
    else { return [focus] }

    let direction = direction(from: focusedFrame, to: target.frame)
    var commands = ["move --window-id \(picked) \(direction.rawValue)"]
    let targetIsSibling = direction.isHorizontal ? target.window.isHorizontal : target.window.isVertical
    if targetIsSibling {
        commands.append("join-with --window-id \(picked) \(direction.rawValue)")
        commands.append("layout --window-id \(picked) \(direction.isHorizontal ? "v_accordion" : "h_accordion")")
    } else {
        commands.append("move --window-id \(picked) \(direction.rawValue)")
    }
    commands.append(focus)
    return commands
}

public func visibleFraction(of id: UInt32, in stack: [ScreenWindow]) -> Double {
    guard let index = stack.firstIndex(where: { $0.id == id }) else { return 0 }
    let target = stack[index].frame
    let total = area(target)
    guard total > 0 else { return 0 }
    var pieces = [target]
    for above in stack[..<index] {
        pieces = pieces.flatMap { subtract(above.frame, from: $0) }
        if pieces.isEmpty { return 0 }
    }
    return pieces.reduce(0) { $0 + area($1) } / total
}

func frame(of id: UInt32, in stack: [ScreenWindow]) -> CGRect? {
    stack.first(where: { $0.id == id })?.frame
}

func subtract(_ cut: CGRect, from rect: CGRect) -> [CGRect] {
    let hole = rect.intersection(cut)
    if hole.isNull || hole.isEmpty { return [rect] }
    var pieces: [CGRect] = []
    if hole.minY > rect.minY {
        pieces.append(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: hole.minY - rect.minY))
    }
    if hole.maxY < rect.maxY {
        pieces.append(CGRect(x: rect.minX, y: hole.maxY, width: rect.width, height: rect.maxY - hole.maxY))
    }
    if hole.minX > rect.minX {
        pieces.append(CGRect(x: rect.minX, y: hole.minY, width: hole.minX - rect.minX, height: hole.height))
    }
    if hole.maxX < rect.maxX {
        pieces.append(CGRect(x: hole.maxX, y: hole.minY, width: rect.maxX - hole.maxX, height: hole.height))
    }
    return pieces
}

func overlapRatio(_ rect: CGRect, _ other: CGRect) -> Double {
    let total = area(rect)
    guard total > 0 else { return 0 }
    let shared = rect.intersection(other)
    return shared.isNull ? 0 : area(shared) / total
}

func direction(from source: CGRect, to target: CGRect) -> Direction {
    let dx = target.midX - source.midX
    let dy = target.midY - source.midY
    if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
    return dy >= 0 ? .down : .up
}

private func area(_ rect: CGRect) -> Double { Double(rect.width * rect.height) }
private func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }
