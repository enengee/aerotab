import AppKit
import AeroTabCore

struct SwitcherItem {
    let window: WorkspaceWindow
    let aspect: CGFloat
    let icon: CGImage?
}

struct SwitcherGroup {
    let label: String?
    let items: [SwitcherItem]
}

@MainActor
final class SwitcherPanel {
    private enum Metrics {
        static let panelPadding: CGFloat = 18
        static let cellPadding: CGFloat = 8
        static let cellSpacing: CGFloat = 4
        static let rowSpacing: CGFloat = 6
        static let headerHeight: CGFloat = 20
        static let headerGap: CGFloat = 6
        static let iconSize: CGFloat = 18
        static let placeholderIconSize: CGFloat = 56
        static let minThumbHeight: CGFloat = 36
        static let labelFontSize: CGFloat = 13
        static let labelPadding: CGFloat = 12
        static let cornerRadius: CGFloat = 16
        static let cellCornerRadius: CGFloat = 10
        static let rowCornerRadius: CGFloat = 12
        static let thumbnailCornerRadius: CGFloat = 5
        static let minAspect: CGFloat = 0.7
        static let maxAspect: CGFloat = 1.8
    }

    private struct Cell {
        let id: UInt32
        let group: Int
        let frame: CGRect
        let thumbnail: CALayer
        let placeholder: CALayer
    }

    private struct Row {
        let background: CALayer
        let label: CATextLayer
    }

    private let panel: NSPanel
    private let effect: NSVisualEffectView
    private let grid: FlippedView
    private let highlight = CALayer()
    private var cells: [Cell] = []
    private var rows: [Row] = []
    private var selectedGroup: Int?

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

    func show(_ groups: [SwitcherGroup], selected: Int, on screen: NSScreen, thumbnail: (UInt32) -> CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        grid.layer?.sublayers = nil
        cells = []
        rows = []
        selectedGroup = nil

        let area = screen.visibleFrame
        let scale = screen.backingScaleFactor
        let content = groups.count == 1 && groups[0].label == nil
            ? layoutWrapped(groups[0].items, area: area, scale: scale, thumbnail: thumbnail)
            : layoutRows(groups, area: area, scale: scale, thumbnail: thumbnail)
        let size = CGSize(width: content.width + 2 * Metrics.panelPadding, height: content.height + 2 * Metrics.panelPadding)

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
        let group = cells[index].group
        if group != selectedGroup, rows.indices.contains(group) {
            if let previous = selectedGroup, rows.indices.contains(previous) { style(rows[previous], selected: false) }
            style(rows[group], selected: true)
            selectedGroup = group
        }
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

    private func layoutWrapped(_ items: [SwitcherItem], area: CGRect, scale: CGFloat, thumbnail: (UInt32) -> CGImage?) -> CGSize {
        let thumbHeight = baseThumbHeight(area)
        let maxRowWidth = area.width * 0.9 - 2 * Metrics.panelPadding
        let cellHeight = Self.cellHeight(thumbHeight)

        var lines: [[(item: SwitcherItem, width: CGFloat)]] = [[]]
        var lineWidth: CGFloat = 0
        for item in items {
            let width = Self.cellWidth(item, thumbHeight: thumbHeight)
            let added = lines[lines.count - 1].isEmpty ? width : width + Metrics.cellSpacing
            if lineWidth + added > maxRowWidth, !lines[lines.count - 1].isEmpty {
                lines.append([(item, width)])
                lineWidth = width
            } else {
                lines[lines.count - 1].append((item, width))
                lineWidth += added
            }
        }

        let lineWidths = lines.map(Self.rowWidth)
        let contentWidth = lineWidths.max() ?? 0
        grid.layer?.addSublayer(highlight)
        var y = Metrics.panelPadding
        for (lineIndex, line) in lines.enumerated() {
            var x = Metrics.panelPadding + (contentWidth - lineWidths[lineIndex]) / 2
            for (item, width) in line {
                let frame = CGRect(x: x, y: y, width: width, height: cellHeight)
                cells.append(makeCell(item, group: 0, frame: frame, scale: scale, image: thumbnail(item.window.id)))
                x += width + Metrics.cellSpacing
            }
            y += cellHeight + Metrics.cellSpacing
        }
        let contentHeight = cellHeight * CGFloat(lines.count) + Metrics.cellSpacing * CGFloat(lines.count - 1)
        return CGSize(width: contentWidth, height: contentHeight)
    }

    private func layoutRows(_ groups: [SwitcherGroup], area: CGRect, scale: CGFloat, thumbnail: (UInt32) -> CGImage?) -> CGSize {
        let font = NSFont.systemFont(ofSize: Metrics.labelFontSize, weight: .bold)
        let labelTextWidth = groups.map { (($0.label ?? "") as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let labelWidth = min(max(ceil(labelTextWidth) + 2 * Metrics.labelPadding, 60), 200)

        let maxWidth = area.width * 0.92 - 2 * Metrics.panelPadding - labelWidth
        let maxHeight = area.height * 0.9 - 2 * Metrics.panelPadding - Metrics.rowSpacing * CGFloat(groups.count - 1)
        let chrome = Self.cellHeight(0)
        var thumbHeight = min(baseThumbHeight(area), maxHeight / CGFloat(groups.count) - chrome)
        for group in groups {
            let factors = group.items.reduce(0) { $0 + Self.aspectFactor($1) }
            let fixed = CGFloat(group.items.count) * 2 * Metrics.cellPadding + Metrics.cellSpacing * CGFloat(group.items.count - 1)
            thumbHeight = min(thumbHeight, (maxWidth - fixed) / factors)
        }
        thumbHeight = max(floor(thumbHeight), Metrics.minThumbHeight)
        let cellHeight = Self.cellHeight(thumbHeight)

        let rowWidths = groups.map { group in
            Self.rowWidth(group.items.map { ($0, Self.cellWidth($0, thumbHeight: thumbHeight)) })
        }
        let contentWidth = labelWidth + (rowWidths.max() ?? 0)

        var y = Metrics.panelPadding
        for group in groups {
            let rowFrame = CGRect(x: Metrics.panelPadding, y: y, width: contentWidth, height: cellHeight)
            let background = CALayer()
            background.frame = rowFrame.insetBy(dx: -4, dy: -2)
            background.cornerRadius = Metrics.rowCornerRadius
            let label = CATextLayer()
            label.frame = CGRect(x: rowFrame.minX + Metrics.labelPadding, y: rowFrame.midY - 9,
                                 width: labelWidth - 2 * Metrics.labelPadding, height: 18)
            label.string = group.label
            label.font = font
            label.fontSize = Metrics.labelFontSize
            label.truncationMode = .end
            label.contentsScale = scale
            let row = Row(background: background, label: label)
            style(row, selected: false)
            grid.layer?.addSublayer(background)
            grid.layer?.addSublayer(label)
            rows.append(row)
            y += cellHeight + Metrics.rowSpacing
        }
        grid.layer?.addSublayer(highlight)

        y = Metrics.panelPadding
        for (groupIndex, group) in groups.enumerated() {
            var x = Metrics.panelPadding + labelWidth
            for item in group.items {
                let width = Self.cellWidth(item, thumbHeight: thumbHeight)
                let frame = CGRect(x: x, y: y, width: width, height: cellHeight)
                cells.append(makeCell(item, group: groupIndex, frame: frame, scale: scale, image: thumbnail(item.window.id)))
                x += width + Metrics.cellSpacing
            }
            y += cellHeight + Metrics.rowSpacing
        }
        let contentHeight = cellHeight * CGFloat(groups.count) + Metrics.rowSpacing * CGFloat(groups.count - 1)
        return CGSize(width: contentWidth, height: contentHeight)
    }

    private func style(_ row: Row, selected: Bool) {
        row.background.backgroundColor = selected ? NSColor.white.withAlphaComponent(0.1).cgColor : nil
        row.background.borderColor = selected ? NSColor.white.withAlphaComponent(0.18).cgColor : nil
        row.background.borderWidth = selected ? 1 : 0
        row.label.foregroundColor = NSColor.white.withAlphaComponent(selected ? 1 : 0.45).cgColor
    }

    private func baseThumbHeight(_ area: CGRect) -> CGFloat {
        min(max(area.height * 0.18, 110), 200)
    }

    private static func aspectFactor(_ item: SwitcherItem) -> CGFloat {
        min(max(item.aspect, Metrics.minAspect), Metrics.maxAspect)
    }

    private static func cellWidth(_ item: SwitcherItem, thumbHeight: CGFloat) -> CGFloat {
        aspectFactor(item) * thumbHeight + 2 * Metrics.cellPadding
    }

    private static func cellHeight(_ thumbHeight: CGFloat) -> CGFloat {
        Metrics.headerHeight + Metrics.headerGap + thumbHeight + 2 * Metrics.cellPadding
    }

    private static func rowWidth(_ row: [(item: SwitcherItem, width: CGFloat)]) -> CGFloat {
        row.reduce(0) { $0 + $1.width } + Metrics.cellSpacing * CGFloat(max(row.count - 1, 0))
    }

    private func makeCell(_ item: SwitcherItem, group: Int, frame: CGRect, scale: CGFloat, image: CGImage?) -> Cell {
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
        let thumbTop = inner.minY + Metrics.headerHeight + Metrics.headerGap
        thumbnail.frame = CGRect(x: inner.minX, y: thumbTop, width: inner.width, height: inner.maxY - thumbTop)
        thumbnail.contentsGravity = .resizeAspect
        thumbnail.contentsScale = scale
        thumbnail.cornerRadius = Metrics.thumbnailCornerRadius
        thumbnail.masksToBounds = true
        thumbnail.contents = image

        let placeholderSize = min(Metrics.placeholderIconSize, thumbnail.bounds.height * 0.7)
        let placeholder = CALayer()
        placeholder.frame = CGRect(x: thumbnail.bounds.midX - placeholderSize / 2, y: thumbnail.bounds.midY - placeholderSize / 2,
                                   width: placeholderSize, height: placeholderSize)
        placeholder.contents = item.icon
        placeholder.contentsGravity = .resizeAspect
        placeholder.contentsScale = scale
        placeholder.opacity = 0.6
        placeholder.isHidden = image != nil
        thumbnail.addSublayer(placeholder)

        grid.layer?.addSublayer(icon)
        grid.layer?.addSublayer(title)
        grid.layer?.addSublayer(thumbnail)
        return Cell(id: item.window.id, group: group, frame: frame, thumbnail: thumbnail, placeholder: placeholder)
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
