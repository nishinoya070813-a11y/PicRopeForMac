import AppKit

/// 悬停预览：鼠标在绳子上的截图停留 0.35s，在绳子下方弹出原比例大图；移开即消失
final class ImagePreview {
    static let shared = ImagePreview()

    private let panel: NSPanel
    private let imageView = NSImageView()
    private var showWork: DispatchWorkItem?

    private init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true   // 不抢绳子的悬停和点击
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView = imageView
    }

    /// 悬停确认后再弹出，鼠标只是划过时不闪
    func schedule(_ item: CaptureItem, from view: NSView) {
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view else { return }
            self.show(item, from: view)
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func hide() {
        showWork?.cancel()
        showWork = nil
        panel.orderOut(nil)
    }

    private func show(_ item: CaptureItem, from view: NSView) {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
        let img = item.image.size
        guard img.width > 0, img.height > 0 else { return }

        let thumb = window.convertToScreen(view.convert(view.bounds, to: nil))
        let ropeBottom = window.frame.minY
        let vis = screen.visibleFrame
        let gap: CGFloat = 8

        // 保持原比例：宽不超过屏幕 60%，高不超过绳子下方可用空间，小图不放大
        let maxW = vis.width * 0.6
        let maxH = max(120, ropeBottom - gap - vis.minY - 10)
        let scale = min(1, maxW / img.width, maxH / img.height)
        let size = NSSize(width: floor(img.width * scale), height: floor(img.height * scale))

        // 水平对准悬停的缩略图，超出屏幕时往里收
        let x = min(max(thumb.midX - size.width / 2, vis.minX + 10), vis.maxX - size.width - 10)
        let y = max(vis.minY, ropeBottom - gap - size.height)

        imageView.image = item.image
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}
