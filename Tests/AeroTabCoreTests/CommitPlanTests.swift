import CoreGraphics
import Testing
@testable import AeroTabCore

private let leftFront = CGRect(x: 0, y: 30, width: 950, height: 1050)
private let leftBack = CGRect(x: 0, y: 0, width: 950, height: 1050)
private let rightFront = CGRect(x: 970, y: 30, width: 950, height: 1050)
private let rightBack = CGRect(x: 970, y: 0, width: 950, height: 1050)

private func window(_ id: UInt32, _ layout: String) -> WorkspaceWindow {
    WorkspaceWindow(id: id, pid: 1, appName: "App", title: "w\(id)", layout: layout)
}

@Test func pickingFocusedWindowDoesNothing() {
    let commands = commitCommands(
        picked: 1, focused: 1,
        windows: [window(1, "h_tiles"), window(2, "h_tiles")],
        stack: [ScreenWindow(id: 1, frame: leftBack), ScreenWindow(id: 2, frame: rightBack)]
    )
    #expect(commands.isEmpty)
}

@Test func visibleWindowIsOnlyFocused() {
    let commands = commitCommands(
        picked: 2, focused: 1,
        windows: [window(1, "h_tiles"), window(2, "h_tiles")],
        stack: [ScreenWindow(id: 1, frame: leftBack), ScreenWindow(id: 2, frame: rightBack)]
    )
    #expect(commands == ["focus --window-id 2"])
}

@Test func hiddenWindowBehindFocusedMovesIntoOtherAccordionColumn() {
    let commands = commitCommands(
        picked: 2, focused: 1,
        windows: [window(1, "v_accordion"), window(2, "v_accordion"), window(3, "v_accordion"), window(4, "v_accordion")],
        stack: [
            ScreenWindow(id: 1, frame: leftFront),
            ScreenWindow(id: 3, frame: rightFront),
            ScreenWindow(id: 2, frame: leftBack),
            ScreenWindow(id: 4, frame: rightBack),
        ]
    )
    #expect(commands == ["move --window-id 2 right", "move --window-id 2 right", "focus --window-id 2"])
}

@Test func hiddenWindowBehindFocusedOnRightMovesLeft() {
    let commands = commitCommands(
        picked: 4, focused: 3,
        windows: [window(1, "v_accordion"), window(2, "v_accordion"), window(3, "v_accordion"), window(4, "v_accordion")],
        stack: [
            ScreenWindow(id: 3, frame: rightFront),
            ScreenWindow(id: 1, frame: leftFront),
            ScreenWindow(id: 4, frame: rightBack),
            ScreenWindow(id: 2, frame: leftBack),
        ]
    )
    #expect(commands == ["move --window-id 4 left", "move --window-id 4 left", "focus --window-id 4"])
}

@Test func singleWindowColumnBecomesAccordionWithPickedWindow() {
    let commands = commitCommands(
        picked: 2, focused: 1,
        windows: [window(1, "v_accordion"), window(2, "v_accordion"), window(3, "h_tiles")],
        stack: [
            ScreenWindow(id: 1, frame: leftFront),
            ScreenWindow(id: 3, frame: CGRect(x: 970, y: 0, width: 950, height: 1080)),
            ScreenWindow(id: 2, frame: leftBack),
        ]
    )
    #expect(commands == [
        "move --window-id 2 right",
        "join-with --window-id 2 right",
        "layout --window-id 2 v_accordion",
        "focus --window-id 2",
    ])
}

@Test func singleAccordionBringsPickedWindowForward() {
    let commands = commitCommands(
        picked: 2, focused: 1,
        windows: [window(1, "v_accordion"), window(2, "v_accordion")],
        stack: [
            ScreenWindow(id: 1, frame: CGRect(x: 0, y: 30, width: 1920, height: 1050)),
            ScreenWindow(id: 2, frame: CGRect(x: 0, y: 0, width: 1920, height: 1050)),
        ]
    )
    #expect(commands == ["focus --window-id 2"])
}

@Test func hiddenWindowInOtherColumnIsOnlyFocused() {
    let commands = commitCommands(
        picked: 4, focused: 1,
        windows: [window(1, "v_accordion"), window(2, "v_accordion"), window(3, "v_accordion"), window(4, "v_accordion")],
        stack: [
            ScreenWindow(id: 1, frame: leftFront),
            ScreenWindow(id: 3, frame: rightFront),
            ScreenWindow(id: 2, frame: leftBack),
            ScreenWindow(id: 4, frame: rightBack),
        ]
    )
    #expect(commands == ["focus --window-id 4"])
}

@Test func visibleFractionSubtractsEveryWindowAbove() {
    let stack = [
        ScreenWindow(id: 1, frame: CGRect(x: 0, y: 0, width: 50, height: 100)),
        ScreenWindow(id: 2, frame: CGRect(x: 25, y: 0, width: 50, height: 100)),
        ScreenWindow(id: 3, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
    ]
    #expect(visibleFraction(of: 3, in: stack) == 0.25)
    #expect(visibleFraction(of: 1, in: stack) == 1)
}

@Test func recencyOrderPutsFocusedFirstThenHistoryThenTreeOrder() {
    let windows = [window(1, "h_tiles"), window(2, "h_tiles"), window(3, "h_tiles"), window(4, "h_tiles")]
    let ordered = recencyOrder(windows, focused: 3, history: [2, 3, 99])
    #expect(ordered.map(\.id) == [3, 2, 1, 4])
}
