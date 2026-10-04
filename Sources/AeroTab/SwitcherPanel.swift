import AppKit
import AeroTabCore

struct SwitcherItem {
    let window: WorkspaceWindow
    let aspect: CGFloat
    let icon: CGImage?
}

@MainActor
final class SwitcherPanel {
    private enum Metrics {
        static let panelPadding: CGFloat = 18
        static let cellPadding: CGFloat = 8
        static let cellSpacing: CGFloat = 4
        static let headerHeight: CGFloat = 20
        static let headerGap: CGFloat = 6
        static let iconSize: CGFloat = 18
        static let placeholderIconSize: CGFloat = 56
        static let cornerRadius: CGFloat = 16
        static let cellCornerRadius: CGFloat = 10
        static let thumbnailCornerRadius: CGFloat = 5
    }

    private struct Cell {
        let id: UInt32
        let frame: CGRect
        let thumbnail: CALayer
        let placeholder: CALayer
    }

    private let panel: NSPanel
    private let effect: NSVisualEffectView
    private let grid: FlippedView
    private let highlight = CALayer()
    private var cells: [Cell] = []

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)

        effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active

        grid = FlippedView()
        grid.wantsLayer = true
        grid.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        effect.addSubview(grid)
        panel.contentView = effect

        highlight.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        highlight.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        highlight.borderWidth = 1
        highlight.cornerRadius = Metrics.cellCornerRadius

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    func show(_ items: [SwitcherItem], selected: Int, on screen: NSScreen, thumbnail: (UInt32) -> CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let area = screen.visibleFrame
        let thumbHeight = min(max(area.height * 0.18, 110), 200)
        let maxRowWidth = area.width * 0.9 - 2 * Metrics.panelPadding
        let cellHeight = Metrics.headerHeight + Metrics.headerGap + thumbHeight + 2 * Metrics.cellPadding

        var rows: [[(item: SwitcherItem, width: CGFloat)]] = [[]]
        var rowWidth: CGFloat = 0
        for item in items {
            let thumbWidth = min(max(thumbHeight * item.aspect, thumbHeight * 0.7), thumbHeight * 1.8)
            let width = thumbWidth + 2 * Metrics.cellPadding
            let added = rows[rows.count - 1].isEmpty ? width : width + Metrics.cellSpacing
            if rowWidth + added > maxRowWidth, !rows[rows.count - 1].isEmpty {
                rows.append([(item, width)])
                rowWidth = width
            } else {
                rows[rows.count - 1].append((item, width))
                rowWidth += added
            }
        }

        let rowWidths = rows.map { row in
            row.reduce(0) { $0 + $1.width } + Metrics.cellSpacing * CGFloat(max(row.count - 1, 0))
        }
        let contentWidth = rowWidths.max() ?? 0
        let contentHeight = cellHeight * CGFloat(rows.count) + Metrics.cellSpacing * CGFloat(rows.count - 1)
        let size = CGSize(width: contentWidth + 2 * Metrics.panelPadding, height: contentHeight + 2 * Metrics.panelPadding)

        grid.layer?.sublayers = nil
        grid.layer?.addSublayer(highlight)
        cells = []
        let scale = screen.backingScaleFactor
        var y = Metrics.panelPadding
        for (rowIndex, row) in rows.enumerated() {
            var x = Metrics.panelPadding + (contentWidth - rowWidths[rowIndex]) / 2
            for (item, width) in row {
                let frame = CGRect(x: x, y: y, width: width, height: cellHeight)
                cells.append(makeCell(item, frame: frame, scale: scale, image: thumbnail(item.window.id)))
                x += width + Metrics.cellSpacing
            }
            y += cellHeight + Metrics.cellSpacing
        }

        let origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        effect.frame = CGRect(origin: .zero, size: size)
        effect.maskImage = Self.roundedMask(size: size, radius: Metrics.cornerRadius)
        grid.frame = effect.bounds
        select(selected)
        panel.orderFrontRegardless()
    }

    func select(_ index: Int) {
        guard cells.indices.contains(index) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.frame = cells[index].frame
        CATransaction.commit()
    }

    func setThumbnail(_ image: CGImage, for id: UInt32) {
        guard let cell = cells.first(where: { $0.id == id }) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cell.thumbnail.contents = image
        cell.placeholder.isHidden = true
        CATransaction.commit()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func makeCell(_ item: SwitcherItem, frame: CGRect, scale: CGFloat, image: CGImage?) -> Cell {
        let inner = frame.insetBy(dx: Metrics.cellPadding, dy: Metrics.cellPadding)

        let icon = CALayer()
        icon.frame = CGRect(x: inner.minX, y: inner.minY + (Metrics.headerHeight - Metrics.iconSize) / 2,
                            width: Metrics.iconSize, height: Metrics.iconSize)
        icon.contents = item.icon
        icon.contentsGravity = .resizeAspect
        icon.contentsScale = scale

        let title = CATextLayer()
        let titleX = icon.frame.maxX + 6
        title.frame = CGRect(x: titleX, y: inner.minY + 2, width: inner.maxX - titleX, height: Metrics.headerHeight)
        title.string = item.window.title.isEmpty ? item.window.appName : item.window.title
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        title.fontSize = 12
        title.foregroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        title.truncationMode = .end
        title.isWrapped = false
        title.contentsScale = scale

        let thumbnail = CALayer()
        thumbnail.frame = CGRect(x: inner.minX, y: inner.minY + Metrics.headerHeight + Metrics.headerGap,
                                 width: inner.width, height: inner.maxY - (inner.minY + Metrics.headerHeight + Metrics.headerGap))
        thumbnail.contentsGravity = .resizeAspect
        thumbnail.contentsScale = scale
        thumbnail.cornerRadius = Metrics.thumbnailCornerRadius
        thumbnail.masksToBounds = true
        thumbnail.contents = image

        let placeholder = CALayer()
        placeholder.frame = CGRect(x: thumbnail.bounds.midX - Metrics.placeholderIconSize / 2,
                                   y: thumbnail.bounds.midY - Metrics.placeholderIconSize / 2,
                                   width: Metrics.placeholderIconSize, height: Metrics.placeholderIconSize)
        placeholder.contents = item.icon
        placeholder.contentsGravity = .resizeAspect
        placeholder.contentsScale = scale
        placeholder.opacity = 0.6
        placeholder.isHidden = image != nil
        thumbnail.addSublayer(placeholder)

        grid.layer?.addSublayer(icon)
        grid.layer?.addSublayer(title)
        grid.layer?.addSublayer(thumbnail)
        return Cell(id: item.window.id, frame: frame, thumbnail: thumbnail, placeholder: placeholder)
    }

    private static func roundedMask(size: CGSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
