import AppKit

/// 绳子上的单个截图：固定正方形（中心裁剪，无视原比例）
/// 单击复制、双击钉桌面、右键菜单
final class RopeItemView: NSImageView {
    let item: CaptureItem
    /// 方块边长上限（放不下时会整体缩小）
    static let maxSide: CGFloat = 84
    private let side: CGFloat
    private let deleteBadge: DeleteBadge

    init(item: CaptureItem, side: CGFloat = RopeItemView.maxSide) {
        self.item = item
        self.side = side
        // 右上角删除按钮：随方块大小缩放，12–18pt
        let d = max(12, min(18, (side * 0.28).rounded()))
        self.deleteBadge = DeleteBadge(frame: NSRect(x: side - d - 3, y: side - d - 3, width: d, height: d))
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        deleteBadge.isHidden = true
        deleteBadge.onClick = { [weak self] in
            guard let self else { return }
            ImagePreview.shared.hide()
            CaptureStore.shared.remove(self.item)
        }
        addSubview(deleteBadge)
        self.image = RopeItemView.cachedSquare(item, side: side)
        self.imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 3
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        // 悬停放大动画
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    /// 裁剪结果缓存：新截图挂上时只裁新的那张，不必重裁整条绳子
    private static var squareCache: [String: NSImage] = [:]

    private static func cachedSquare(_ item: CaptureItem, side: CGFloat) -> NSImage {
        let key = "\(item.id.uuidString)-\(Int(side))"
        if let hit = squareCache[key] { return hit }
        if squareCache.count > 300 { squareCache.removeAll() }
        let img = squareCropped(item.image, side: side)
        squareCache[key] = img
        return img
    }

    /// 中心裁剪为正方形（无视原比例）
    private static func squareCropped(_ image: NSImage, side: CGFloat) -> NSImage {
        let s = min(image.size.width, image.size.height)
        let srcRect = NSRect(x: (image.size.width - s) / 2,
                             y: (image.size.height - s) / 2,
                             width: s, height: s)
        let cropped = NSImage(size: NSSize(width: side, height: side))
        cropped.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                  from: srcRect, operation: .copy, fraction: 1)
        cropped.unlockFocus()
        return cropped
    }

    // MARK: - 单击复制 / 双击钉桌面
    // 注意：不调用 super 的鼠标事件处理，NSImageView 默认实现会吞掉后续事件

    override func mouseDown(with event: NSEvent) {
        // 保留钩子：目前单击/双击均在 mouseUp 处理
    }

    /// 单击复制延迟判定：等 0.22s 确认没有第二击（双击）才执行，避免双击钉图时先复制
    private var clickTimer: Timer?

    override func mouseUp(with event: NSEvent) {
        ImagePreview.shared.hide()
        clickTimer?.invalidate()
        if event.clickCount == 2 {
            // 双击：只钉图，不复制
            PinController.shared.pin(item: item)
        } else {
            // 单击：延迟执行，若第二击在延迟窗口内到来则被取消
            clickTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
                self?.copyToClipboard()
            }
        }
    }

    func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.image])
        ClipboardMonitorBridge.shared.markSelfWrite()
        LightNotice.show("已复制")
    }

    // MARK: - 悬停高亮（被选中提示）

    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        // 高亮：强调色边框 + 轻微放大
        animateHover(true)
        deleteBadge.isHidden = false
        ImagePreview.shared.schedule(item, from: self)
    }

    /// AppKit 管理的图层默认关闭隐式动画，直接改 transform 会“跳”，这里显式加动画
    private func animateHover(_ on: Bool) {
        guard let layer else { return }
        // 以方块中心为基准缩放（与 anchorPoint 设置无关）
        let w = layer.bounds.width, h = layer.bounds.height
        let cx = (0.5 - layer.anchorPoint.x) * w
        let cy = (0.5 - layer.anchorPoint.y) * h
        let target = on
            ? CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-cx, -cy, 0),
                                                      CATransform3DMakeScale(1.08, 1.08, 1)),
                                  CATransform3DMakeTranslation(cx, cy, 0))
            : CATransform3DIdentity

        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = layer.presentation()?.transform ?? layer.transform
        anim.toValue = target
        anim.duration = 0.14
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = target
        layer.borderColor = on ? NSColor.controlAccentColor.cgColor
                               : NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer.borderWidth = on ? 2 : 1
        CATransaction.commit()
        layer.add(anim, forKey: "hover")
    }

    override func mouseExited(with event: NSEvent) {
        ImagePreview.shared.hide()
        deleteBadge.isHidden = true
        animateHover(false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - 右键菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        ImagePreview.shared.hide()
        let menu = NSMenu()
        menu.addItem(mi("用预览打开", #selector(openMenu)))
        menu.addItem(mi("复制", #selector(copyToClipboardMenu)))
        menu.addItem(mi("钉在桌面", #selector(pinMenu)))
        menu.addItem(mi("存储到…", #selector(saveMenu)))
        menu.addItem(.separator())
        menu.addItem(mi("删除此图片", #selector(removeMenu)))
        menu.addItem(mi("移除除此之外所有图片", #selector(removeOthersMenu)))
        menu.addItem(mi("删除绳子上所有图片", #selector(removeAllMenu)))
        return menu
    }

    private func mi(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func copyToClipboardMenu() { copyToClipboard() }
    @objc private func pinMenu() { PinController.shared.pin(item: item) }
    @objc private func removeMenu() { CaptureStore.shared.remove(item) }
    @objc private func removeOthersMenu() { CaptureStore.shared.removeAll(except: item) }
    @objc private func removeAllMenu() { CaptureStore.shared.clear() }

    /// 写到临时目录再用默认看图应用（通常是“预览”）打开，不碰绳子自己的存档文件
    @objc private func openMenu() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.fileName)
        if (try? item.data.write(to: url)) != nil {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func saveMenu() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "PicRope-\(Int(item.createdAt.timeIntervalSince1970)).png"
        if panel.runModal() == .OK, let url = panel.url {
            try? item.data.write(to: url)
        }
    }
}
