import Testing
@testable import AeroTabCore

private func window(_ id: UInt32, _ workspace: String) -> WorkspaceWindow {
    WorkspaceWindow(id: id, pid: 1, appName: "App", title: "w\(id)", layout: "h_tiles", workspace: workspace)
}

private let all = [
    window(1, "a"), window(2, "a"),
    window(3, "b"),
    window(4, "c"), window(5, "c"), window(6, "c"),
]

@Test func focusedWorkspaceComesFirstThenWorkspacesByMostRecentWindow() {
    let groups = workspaceGroups(all, focusedWorkspace: "c", focused: 5, history: [5, 3, 2, 6, 1])
    #expect(groups.map(\.workspace) == ["c", "b", "a"])
    #expect(groups.map { $0.windows.map(\.id) } == [[5, 6, 4], [3], [2, 1]])
}

@Test func workspacesWithoutHistoryKeepAeroSpaceOrderAfterKnownOnes() {
    let groups = workspaceGroups(all, focusedWorkspace: "b", focused: 3, history: [3, 6])
    #expect(groups.map(\.workspace) == ["b", "c", "a"])
}

@Test func firstForwardTapSelectsPreviouslyUsedWindowEvenInAnotherWorkspace() {
    let flat = workspaceGroups(all, focusedWorkspace: "c", focused: 5, history: [5, 3, 2, 6, 1]).flatMap(\.windows)
    #expect(flat.map(\.id) == [5, 6, 4, 3, 2, 1])
    #expect(initialSelection(flat, focused: 5, history: [5, 3, 2, 6, 1], backward: false) == 3)
    #expect(initialSelection(flat, focused: 5, history: [5, 3, 2, 6, 1], backward: true) == 5)
}

@Test func firstForwardTapWithoutHistoryStepsPastFocusedWindow() {
    #expect(initialSelection(all, focused: 1, history: [], backward: false) == 1)
    #expect(initialSelection([window(1, "a")], focused: 1, history: [1], backward: false) == 0)
}

@Test func workspaceJumpLandsOnFirstWindowForwardAndLastWindowBackwardWithWrap() {
    let ring = Ring(groupSizes: [3, 1, 2])
    #expect(ring.jumpWorkspace(from: 1, forward: true) == 3)
    #expect(ring.jumpWorkspace(from: 3, forward: true) == 4)
    #expect(ring.jumpWorkspace(from: 5, forward: true) == 0)
    #expect(ring.jumpWorkspace(from: 4, forward: false) == 3)
    #expect(ring.jumpWorkspace(from: 0, forward: false) == 5)
    #expect(ring.step(5, by: 1) == 0)
    #expect(ring.step(0, by: -1) == 5)
}
