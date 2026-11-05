import AppKit

/// 复制成功的轻量提示：屏幕居中、深色半透明胶囊、淡入淡出。
/// show 返回提示本身，可以用 update 原地改成结果（例如「识别中…」→「已复制」），不会弹出第二个。
final class LightNotice {
    private static let height: CGFloat = 60

    private let panel: NSPanel
    private let content: NSView
    private let icon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let field = NSTextField(labelWithString: "")
    private var dismissWork: DispatchWorkItem?

    /// duration 为 nil 时一直显示，等 update 给出结果后再自动消失；loading 时用转圈代替图标
    @discardableResult
    static func show(_ text: String, icon symbol: String = "checkmark.circle.fill",
                     duration: TimeInterval? = 0.65, loading: Bool = false) -> LightNotice {
        let notice = LightNotice()
        notice.apply(text, icon: symbol, loading: loading)
        notice.panel.alphaValue = 0
        notice.panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            notice.panel.animator().alphaValue = 1
        }
        if let duration { notice.scheduleDismiss(after: 0.18 + duration) }
        return notice
    }

    /// 原地换成新内容（宽度跟着变、保持居中），停留 duration 秒后淡出
    func update(_ text: String, icon symbol: String = "checkmark.circle.fill",
                duration: TimeInterval = 1.5) {
        apply(text, icon: symbol, loading: false)
        scheduleDismiss(after: duration)
    }

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: Self.height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true

        content = NSView(frame: panel.contentLayoutRect)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        content.layer?.cornerRadius = 16
        content.layer?.masksToBounds = true

        icon.frame = NSRect(x: 20, y: 18, width: 24, height: 24)
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.appearance = NSAppearance(named: .darkAqua)   // 深色背景上转圈要是白色
        spinner.frame = NSRect(x: 24, y: 22, width: 16, height: 16)
        spinner.isDisplayedWhenStopped = false
        content.addSubview(spinner)

        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.textColor = .white
        content.addSubview(field)

        panel.contentView = content
    }

    private func apply(_ text: String, icon symbol: String, loading: Bool) {
        field.stringValue = text
        field.sizeToFit()
        field.frame.origin = NSPoint(x: 52, y: Self.height / 2 - field.frame.height / 2)

        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.isHidden = loading
        if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }

        // 先量文字宽度，提示框跟着变宽，长提示不会被截断；屏幕居中（略偏上，避开视线中心遮挡）
        let width = max(160, 52 + field.frame.width + 24)
        var origin = NSPoint.zero
        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            origin = NSPoint(x: vis.midX - width / 2, y: vis.midY - 30 + vis.height * 0.08)
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: Self.height)), display: true)
        content.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissWork?.cancel()
        // work 持有 self，提示消失前不会被释放
        let work = DispatchWorkItem { [self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { [self] in
                panel.orderOut(nil)
                dismissWork = nil   // 断开 self ↔ work 的互相引用，让提示被释放
            })
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
