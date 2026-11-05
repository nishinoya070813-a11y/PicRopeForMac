import AppKit

/// 截图右上角的删除小按钮（悬停时才显示）
final class DeleteBadge: NSButton {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        let config = NSImage.SymbolConfiguration(paletteColors: [.white, NSColor.black.withAlphaComponent(0.65)])
        image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "删除")?
            .withSymbolConfiguration(config)
        toolTip = "删除此图片"
        target = self
        action = #selector(tapped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // 绳子面板不抢焦点，第一次点击就要生效
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func tapped() { onClick?() }
}

/// 最新一张截图右边的「清空」（保留收藏）：红色胶囊按钮，深浅背景下都显眼。
/// 点一次变成实心红色「确认清空？」，3 秒内再点才真正清空，防误触
final class ClearAllButton: NSButton {
    private var armed = false
    private var hovering = false
    private var resetWork: DispatchWorkItem?

    init() {
        // 宽度按较长的「确认清空？」定死，切换状态时绳子上的布局不跳
        super.init(frame: NSRect(x: 0, y: 0, width: 116, height: 30))
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.borderWidth = 1.5
        imagePosition = .imageLeading
        imageHugsTitle = true
        target = self
        action = #selector(tapped)
        toolTip = "清空所有未收藏的截图（收藏的保留）"
        disarm()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; restyle() }
    override func mouseExited(with event: NSEvent) { hovering = false; restyle() }

    @objc private func tapped() {
        if armed {
            disarm()
            ImagePreview.shared.hide()
            CaptureStore.shared.clear()
            return
        }
        armed = true
        restyle()
        resetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.disarm() }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    func disarm() {
        resetWork?.cancel()
        armed = false
        restyle()
    }

    /// 平时：淡红底 + 红边红字；悬停加深；待确认：实心红底白字
    private func restyle() {
        let red = NSColor.systemRed
        let fg: NSColor = armed ? .white : red
        let bg: NSColor = armed ? red : red.withAlphaComponent(hovering ? 0.28 : 0.16)
        layer?.backgroundColor = bg.cgColor
        layer?.borderColor = red.cgColor

        let symbol = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [fg]))
        image = NSImage(systemSymbolName: armed ? "exclamationmark.triangle.fill" : "trash.fill",
                        accessibilityDescription: "清空")?.withSymbolConfiguration(symbol)

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        attributedTitle = NSAttributedString(string: armed ? "确认清空？" : "清空",
                                             attributes: [.foregroundColor: fg,
                                                          .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                          .paragraphStyle: style])
    }
}
