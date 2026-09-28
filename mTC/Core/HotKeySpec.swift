import AppKit
import Carbon.HIToolbox

/// Горячая клавиша в читаемом виде, например:
/// `{ "enabled": true, "key": "t", "modifiers": ["control", "option"] }`.
struct HotKeySpec: Codable, Equatable {
    var enabled: Bool
    var key: String
    var modifiers: [String]

    static let showWindowDefault = HotKeySpec(enabled: true, key: "t", modifiers: ["control", "option"])

    var carbonKeyCode: UInt32? {
        Self.keyCodes[key.lowercased()].map(UInt32.init)
    }

    var carbonModifiers: UInt32 {
        normalizedModifiers.reduce(0) { result, modifier in
            switch modifier {
            case "command": return result | UInt32(cmdKey)
            case "option": return result | UInt32(optionKey)
            case "control": return result | UInt32(controlKey)
            case "shift": return result | UInt32(shiftKey)
            default: return result
            }
        }
    }

    /// Для отображения в меню.
    var menuKeyEquivalent: String {
        key.lowercased() == "space" ? " " : key.lowercased()
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        for modifier in normalizedModifiers {
            switch modifier {
            case "command": mask.insert(.command)
            case "option": mask.insert(.option)
            case "control": mask.insert(.control)
            case "shift": mask.insert(.shift)
            default: break
            }
        }
        return mask
    }

    private var normalizedModifiers: [String] {
        modifiers.map { modifier in
            switch modifier.lowercased() {
            case "cmd", "⌘": return "command"
            case "alt", "opt", "⌥": return "option"
            case "ctrl", "⌃": return "control"
            case "⇧": return "shift"
            default: return modifier.lowercased()
            }
        }
    }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "`": kVK_ANSI_Grave, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, ";": kVK_ANSI_Semicolon,
        "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
        "\\": kVK_ANSI_Backslash,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]
}
