import AppKit
import ScreenCaptureKit

@MainActor
final class Thumbnails {
    private var cache: [UInt32: CGImage] = [:]
    private var refresh: Task<[UInt32: SCWindow], Never>?

    func cached(_ id: UInt32) -> CGImage? { cache[id] }

    func forget(_ id: UInt32) { cache[id] = nil }

    func capture(_ ids: [UInt32], maxPixels: CGSize, onImage: @escaping @MainActor (UInt32, CGImage) -> Void) {
        let refresh = Task.detached(priority: .userInitiated) { () -> [UInt32: SCWindow] in
            do {
                let shareable = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                return Dictionary(shareable.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            } catch {
                log("screen capture unavailable: \(error)")
                return [:]
            }
        }
        self.refresh = refresh
        Task { @MainActor in
            let windows = await refresh.value
            guard self.refresh == refresh else { return }
            for id in ids {
                guard let window = windows[id] else { continue }
                Task.detached(priority: .userInitiated) {
                    guard let image = await Self.shoot(window, maxPixels: maxPixels) else { return }
                    await MainActor.run {
                        self.cache[id] = image
                        onImage(id, image)
                    }
                }
            }
        }
    }

    nonisolated private static func shoot(_ window: SCWindow, maxPixels: CGSize) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let size = window.frame.size
        guard size.width > 0, size.height > 0 else { return nil }
        let fit = min(1, maxPixels.width / (size.width * scale), maxPixels.height / (size.height * scale))
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(size.width * scale * fit))
        configuration.height = max(1, Int(size.height * scale * fit))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            log("capture \(window.windowID): \(error)")
            return nil
        }
    }
}
