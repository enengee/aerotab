import AeroTabCore
import Foundation

struct WindowSnapshot {
    let focused: UInt32?
    let focusedWorkspace: String?
    let screenIndex: Int?
    let windows: [WorkspaceWindow]
}

enum AeroSpace {
    static let queue = DispatchQueue(label: "aerotab.aerospace", qos: .userInteractive)

    static func run(_ args: [String]) throws -> AeroSpaceAnswer {
        let answer = try AeroSpaceConnection().run(args)
        if answer.exitCode != 0 {
            throw AeroSpaceError(description: "aerospace \(args.joined(separator: " ")) exited \(answer.exitCode): \(answer.stderr)")
        }
        return answer
    }

    static func eval(_ commands: [String]) throws {
        guard !commands.isEmpty else { return }
        _ = try run(["eval", commands.joined(separator: "; ")])
    }

    static func snapshot(allWorkspaces: Bool) throws -> WindowSnapshot {
        let format = "%{window-id} %{app-pid} %{app-name} %{window-title} %{window-layout} %{workspace}"
        let scope = allWorkspaces ? "--all" : "--workspace focused"
        let answer = try run(["eval", """
            list-windows --focused --format '%{window-id}'; \
            list-workspaces --focused --format '%{workspace}%{tab}%{monitor-appkit-nsscreen-screens-id}'; \
            list-windows \(scope) --json --format '\(format)'
            """])
        let stdout = answer.stdout
        guard let listStart = stdout.hasPrefix("[\n") ? stdout.startIndex : stdout.range(of: "\n[\n").map({ stdout.index(after: $0.lowerBound) }) else {
            throw AeroSpaceError(description: "unexpected list-windows output: \(stdout)")
        }
        var focused: UInt32?
        var focusedWorkspace: String?
        var screenIndex: Int?
        for line in answer.stdout[..<listStart].split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.count == 2 {
                focusedWorkspace = String(fields[0])
                screenIndex = Int(fields[1])
            } else if let id = UInt32(line.trimmingCharacters(in: .whitespaces)) {
                focused = id
            }
        }
        let rows = try JSONSerialization.jsonObject(with: Data(answer.stdout[listStart...].utf8)) as? [[String: Any]] ?? []
        let windows: [WorkspaceWindow] = rows.compactMap { row in
            guard let id = (row["window-id"] as? NSNumber)?.uint32Value else { return nil }
            return WorkspaceWindow(
                id: id,
                pid: (row["app-pid"] as? NSNumber)?.int32Value ?? 0,
                appName: row["app-name"] as? String ?? "",
                title: row["window-title"] as? String ?? "",
                layout: row["window-layout"] as? String ?? "",
                workspace: row["workspace"] as? String ?? ""
            )
        }
        return WindowSnapshot(focused: focused, focusedWorkspace: focusedWorkspace, screenIndex: screenIndex, windows: windows)
    }
}
