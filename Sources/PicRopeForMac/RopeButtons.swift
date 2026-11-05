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

/// 最新一张截图右边的「清空」（保留收藏）：点一次变成「确认清空？」，3 秒内再点才真正清空，防误触
final class ClearAllButton: NSButton {
    private var armed = false
    private var resetWork: DispatchWorkItem?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 84, height: 22))
        bezelStyle = .inline
        image = NSImage(systemSymbolName: "trash", accessibilityDescription: "清空")
        imagePosition = .imageLeading
        controlSize = .small
        font = .systemFont(ofSize: 11, weight: .medium)
        target = self
        action = #selector(tapped)
        toolTip = "清空所有未收藏的截图（收藏的保留）"
        disarm()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func tapped() {
        if armed {
            disarm()
            ImagePreview.shared.hide()
            CaptureStore.shared.clear()
            return
        }
        armed = true
        title = "确认清空？"
        contentTintColor = .systemRed
        resetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.disarm() }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    func disarm() {
        resetWork?.cancel()
        armed = false
        title = "清空"
        contentTintColor = nil
    }
}
