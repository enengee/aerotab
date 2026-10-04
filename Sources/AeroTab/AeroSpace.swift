import AeroTabCore
import Foundation

struct WorkspaceSnapshot {
    let focused: UInt32?
    let windows: [WorkspaceWindow]
    let screenIndex: Int?
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

    static func snapshot() throws -> WorkspaceSnapshot {
        let format = "%{window-id} %{app-pid} %{app-name} %{window-title} %{window-layout} %{monitor-appkit-nsscreen-screens-id}"
        let answer = try run(["eval", "list-windows --focused --format '%{window-id}'; list-windows --workspace focused --json --format '\(format)'"])
        guard let listStart = answer.stdout.firstIndex(of: "[") else {
            throw AeroSpaceError(description: "unexpected list-windows output: \(answer.stdout)")
        }
        let focused = UInt32(answer.stdout[..<listStart].trimmingCharacters(in: .whitespacesAndNewlines))
        let rows = try JSONSerialization.jsonObject(with: Data(answer.stdout[listStart...].utf8)) as? [[String: Any]] ?? []
        var screenIndex: Int?
        let windows: [WorkspaceWindow] = rows.compactMap { row in
            guard let id = (row["window-id"] as? NSNumber)?.uint32Value else { return nil }
            if screenIndex == nil { screenIndex = (row["monitor-appkit-nsscreen-screens-id"] as? NSNumber)?.intValue }
            return WorkspaceWindow(
                id: id,
                pid: (row["app-pid"] as? NSNumber)?.int32Value ?? 0,
                appName: row["app-name"] as? String ?? "",
                title: row["window-title"] as? String ?? "",
                layout: row["window-layout"] as? String ?? ""
            )
        }
        return WorkspaceSnapshot(focused: focused, windows: windows, screenIndex: screenIndex)
    }
}
