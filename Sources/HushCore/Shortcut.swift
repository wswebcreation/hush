import Foundation

/// A global keyboard shortcut. Modifier bits use Carbon values so they pass straight to RegisterEventHotKey.
public struct Shortcut: Codable, Equatable, Sendable {
    public static let cmdKey = 256, shiftKey = 512, optionKey = 2048, controlKey = 4096
    public var keyCode: Int
    public var modifiers: Int
    public var keyLabel: String

    public init(keyCode: Int, modifiers: Int, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }

    /// ⌥⌘R (kVK_ANSI_R = 15)
    public static let `default` = Shortcut(keyCode: 15, modifiers: optionKey | cmdKey, keyLabel: "R")

    /// Key caps in display order, e.g. ["⌃","⌥","⇧","⌘","R"].
    public var keyCaps: [String] {
        var caps: [String] = []
        if modifiers & Shortcut.controlKey != 0 { caps.append("⌃") }
        if modifiers & Shortcut.optionKey != 0 { caps.append("⌥") }
        if modifiers & Shortcut.shiftKey != 0 { caps.append("⇧") }
        if modifiers & Shortcut.cmdKey != 0 { caps.append("⌘") }
        caps.append(keyLabel.uppercased())
        return caps
    }

    public var display: String { keyCaps.joined() }

    /// A global shortcut needs at least one of ⌃ ⌥ ⌘.
    public var isValid: Bool { modifiers & (Shortcut.controlKey | Shortcut.optionKey | Shortcut.cmdKey) != 0 }
}
