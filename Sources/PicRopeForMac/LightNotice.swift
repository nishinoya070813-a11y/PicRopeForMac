import AppKit

/// 复制成功的轻量提示：屏幕居中、深色半透明胶囊、淡入淡出
enum LightNotice {
    static func show(_ text: String, icon symbol: String = "checkmark.circle.fill",
                     duration: TimeInterval = 0.65) {
        // 先量文字宽度，提示框跟着变宽，长提示不再被截断
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.textColor = .white
        field.sizeToFit()
        let width = max(160, 52 + field.frame.width + 24)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 60),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true

        // 内容：图标 + 文字，垂直水平居中
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 60))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        content.layer?.cornerRadius = 16
        content.layer?.masksToBounds = true

        let icon = NSImageView(frame: NSRect(x: 20, y: 18, width: 24, height: 24))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)

        field.frame.origin = NSPoint(x: 52, y: 60 / 2 - field.frame.height / 2)
        content.addSubview(field)

        panel.contentView = content

        // 屏幕居中（略偏上，避开视线中心遮挡）
        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            let x = vis.midX - width / 2
            let y = vis.midY - 30 + vis.height * 0.08
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // 淡入 → 停留 → 淡出
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    panel.orderOut(nil)
                })
            }
        })
    }
}
