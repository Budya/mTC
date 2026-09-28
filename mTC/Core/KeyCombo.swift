import AppKit
import Carbon.HIToolbox

/// Сочетание клавиш: физическая клавиша (или символ) и модификаторы.
///
/// В `hotkeys.json` пишется строкой: `"F5"`, `"shift+F6"`, `"cmd+shift+c"`, `"ctrl+tab"`, `"space"`, `"plus"`.
/// Клавиши с буквами и цифрами хранятся как физические (работают на любой раскладке, в том числе русской).
/// `plus`, `minus`, `asterisk` — символы: срабатывают и с основной клавиатуры, и с цифровой,
/// Shift для них не учитывается (на многих раскладках `+` и `*` набираются с Shift).
struct KeyCombo: Hashable {
    enum Key: Hashable {
        case code(Int)
        case character(String)
    }

    let key: Key
    let modifiers: NSEvent.ModifierFlags

    init(_ key: Key, _ modifiers: NSEvent.ModifierFlags = []) {
        self.key = key
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift])
    }

    static func == (a: KeyCombo, b: KeyCombo) -> Bool {
        a.key == b.key && a.modifiers == b.modifiers
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }

    // MARK: - Нажатие

    /// Совпадает ли нажатие с сочетанием.
    func matches(_ event: NSEvent) -> Bool {
        let pressed = Self.normalized(event.modifierFlags)
        switch key {
        case .code(let code):
            return Int(event.keyCode) == code && pressed == modifiers
        case .character(let character):
            return event.charactersIgnoringModifiers == character && pressed.subtracting(.shift) == modifiers
        }
    }

    /// Сочетание из нажатия (для записи в окне горячих клавиш). Одиночные модификаторы — `nil`.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let modifiers = Self.normalized(event.modifierFlags)
        let character = event.charactersIgnoringModifiers ?? ""
        if Self.characterKeys.values.contains(character), modifiers.isDisjoint(with: [.command, .option, .control]) {
            self.init(.character(character), [])
        } else {
            self.init(.code(Int(event.keyCode)), modifiers)
        }
    }

    private static func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(.deviceIndependentFlagsMask).intersection([.command, .option, .control, .shift])
    }

    // MARK: - Строка в hotkeys.json

    init?(string: String) {
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, !keyName.isEmpty else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "shift", "⇧": modifiers.insert(.shift)
            case "alt", "option", "opt", "⌥": modifiers.insert(.option)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            default: return nil
            }
        }

        if let character = Self.characterKeys[keyName] {
            self.init(.character(character), modifiers)
        } else if let code = Self.namedKeys[keyName] {
            self.init(.code(code), modifiers)
        } else if keyName.hasPrefix("key"), let code = Int(keyName.dropFirst(3)) {
            self.init(.code(code), modifiers)
        } else {
            return nil
        }
    }

    var stringValue: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        switch key {
        case .character(let character):
            parts.append(Self.characterKeys.first { $0.value == character }?.key ?? character)
        case .code(let code):
            parts.append(Self.nameForCode[code] ?? "key\(code)")
        }
        return parts.joined(separator: "+")
    }

    // MARK: - Показ

    /// Для людей: `⌃⌥⇧⌘T`, `F5`, `⇧F6`, `⌘⌫`, `Space`.
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        switch key {
        case .character(let character):
            result += character == "-" ? "−" : character
        case .code(let code):
            result += Self.displayForCode[code] ?? (Self.nameForCode[code]?.uppercased() ?? "#\(code)")
        }
        return result
    }

    // MARK: - Пункты меню

    /// Можно ли показать сочетание как клавишу пункта меню. Только с ⌘: сочетания без ⌘
    /// меню перехватывало бы и в полях ввода.
    var menuKeyEquivalent: (key: String, mask: NSEvent.ModifierFlags)? {
        guard modifiers.contains(.command), case .code(let code) = key, let base = Self.menuCharacter[code] else { return nil }
        // Для знаков с Shift меню ждёт сам знак: ⌘⇧. → «>» с маской ⌘.
        if modifiers.contains(.shift), let shifted = Self.shiftedCharacter[base] {
            return (shifted, modifiers.subtracting(.shift))
        }
        return (base, modifiers)
    }

    /// F1…F19 (с модификаторами или без) — такие сочетания подписываются на кнопках внизу окна.
    var isFunctionKey: Bool {
        if case .code(let code) = key { return Self.functionKeyCodes.contains(code) }
        return false
    }

    /// Для строки меню в статус-баре: любые модификаторы (меню открыто — перехватывать нечего).
    var anyMenuKeyEquivalent: (key: String, mask: NSEvent.ModifierFlags)? {
        guard case .code(let code) = key, let base = Self.menuCharacter[code] else { return nil }
        return (base, modifiers)
    }

    /// Для Carbon RegisterEventHotKey (глобальная клавиша).
    var carbonKeyCode: UInt32? {
        if case .code(let code) = key { return UInt32(code) }
        return nil
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    // MARK: - Таблицы клавиш

    private static let characterKeys: [String: String] = ["plus": "+", "minus": "-", "asterisk": "*"]

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
    ]

    private static let namedKeys: [String: Int] = {
        var keys: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "`": kVK_ANSI_Grave, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
            "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "-": kVK_ANSI_Minus,
            "space": kVK_Space, "enter": kVK_Return, "keypadenter": kVK_ANSI_KeypadEnter, "tab": kVK_Tab,
            "esc": kVK_Escape, "backspace": kVK_Delete, "delete": kVK_ForwardDelete, "insert": kVK_Help,
            "up": kVK_UpArrow, "down": kVK_DownArrow, "left": kVK_LeftArrow, "right": kVK_RightArrow,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]
        for (index, code) in functionKeys.enumerated() {
            keys["f\(index + 1)"] = code
        }
        return keys
    }()

    private static let nameForCode: [Int: String] = Dictionary(namedKeys.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })

    private static let displayForCode: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↵", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Escape: "Esc",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Help: "Insert",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
    ]

    /// Символ клавиши для пункта меню (буквы, цифры, знаки, ↵, ⌫, стрелки не нужны — их в меню не ставим).
    private static let menuCharacter: [Int: String] = {
        var result: [Int: String] = [:]
        for (name, code) in namedKeys where name.count == 1 {
            result[code] = name
        }
        result[kVK_Delete] = "\u{8}"
        result[kVK_Return] = "\r"
        return result
    }()

    private static let shiftedCharacter: [String: String] = [
        ".": ">", ",": "<", "/": "?", ";": ":", "'": "\"", "[": "{", "]": "}", "\\": "|", "`": "~",
        "=": "+", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
    ]
}
