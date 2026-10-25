import Carbon.HIToolbox
import HushCore

/// Global shortcut via Carbon RegisterEventHotKey (works in any app, no accessibility permission needed).
final class HotKeyCenter: @unchecked Sendable {
    static let shared = HotKeyCenter()
    private var ref: EventHotKeyRef?
    private var handler: (() -> Void)?
    private var installed = false

    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) {
        self.handler = handler
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                HotKeyCenter.shared.handler?()
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        let id = EventHotKeyID(signature: OSType(0x48555348), id: 1)  // 'HUSH'
        RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }
}
