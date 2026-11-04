import AppKit

/// 顶边触发：鼠标在绳子所在屏幕的顶边中段停留约 0.1s 即呼出绳子
/// 轮询鼠标位置实现，无需辅助功能权限；只取中段 60% 宽度，避开两侧菜单栏项目
final class EdgeTrigger {
    static let shared = EdgeTrigger()

    private var timer: Timer?
    private var dwellStart: Date?
    private var wasInZone = false

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let rope = RopePanel.shared
        let p = NSEvent.mouseLocation
        let f = rope.anchorScreenFrame
        let inZone = p.y >= f.maxY - 4
            && p.x >= f.minX + f.width * 0.2
            && p.x <= f.maxX - f.width * 0.2

        defer { wasInZone = inZone }

        guard inZone else {
            dwellStart = nil
            // 离开顶边且没移进绳子：稍后收起
            if wasInZone, rope.isVisible, !NSPointInRect(p, rope.panelFrame) {
                rope.scheduleHide(after: 0.6)
            }
            return
        }

        // 停在顶边期间保持显示
        if rope.isVisible {
            rope.cancelHide()
            return
        }
        if dwellStart == nil {
            dwellStart = Date()
        } else if Date().timeIntervalSince(dwellStart!) >= 0.1 {
            dwellStart = nil
            rope.cancelHide()
            rope.show()
        }
    }
}
