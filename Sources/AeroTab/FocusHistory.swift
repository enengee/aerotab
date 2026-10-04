import Foundation

final class FocusHistory {
    private static let capacity = 256

    private(set) var recent: [UInt32] = []

    init(seed: [UInt32]) {
        recent = Array(seed.prefix(Self.capacity))
    }

    func start() {
        let thread = Thread { [weak self] in self?.listen() }
        thread.name = "aerotab.focus-history"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func touch(_ id: UInt32) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        if recent.count > Self.capacity { recent.removeLast() }
    }

    private func listen() {
        while true {
            do {
                let connection = try AeroSpaceConnection()
                try connection.send(["subscribe", "focus-changed"])
                while true {
                    let event = try connection.receiveObject()
                    guard event["_event"] as? String == "focus-changed",
                          let id = (event["windowId"] as? NSNumber)?.uint32Value
                    else { continue }
                    DispatchQueue.main.async { [weak self] in self?.touch(id) }
                }
            } catch {
                log("focus history: \(error)")
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
