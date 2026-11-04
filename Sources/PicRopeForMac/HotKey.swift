import AppKit
import Carbon.HIToolbox

/// 全局快捷键 ⌥⇧R：显示/隐藏绳子
/// 使用 Carbon RegisterEventHotKey，只监听这一个组合键，无需辅助功能权限
enum HotKey {
    private static var ref: EventHotKeyRef?

    static func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { RopePanel.shared.toggle() }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x50524F50), id: 1)  // 'PROP'
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(optionKey | shiftKey), id,
                            GetApplicationEventTarget(), 0, &ref)
    }
}
