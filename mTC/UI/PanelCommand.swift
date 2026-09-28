import AppKit
import Carbon.HIToolbox

/// Команды файловой панели. Клавиши привязываются к командам через `PanelKeyMap`,
/// поэтому позже привязки можно будет вынести в `hotkeys.json`.
enum PanelCommand: String {
    case open
    case goUp
    case switchPanel
    /// Выделить/снять файл под курсором и перейти ниже (Space, Insert).
    case toggleMark
    /// Инвертировать выделение файла под курсором и перейти выше/ниже (⇧↑ / ⇧↓), как в Total Commander.
    case invertMovingUp
    case invertMovingDown
    case markByMask
    case unmarkByMask
    case invertMarks
    case markAll
    case unmarkAll
    /// Если выделено всё — снять выделение, иначе выделить всё (⌘A).
    case toggleMarkAll
    case nextTab
    case previousTab
    /// Файловые операции.
    case quickLook
    /// Esc: закрыть просмотр, если открыт.
    case closePreview
    case makeDirectory
    case copyToOtherPanel
    case moveToOtherPanel
    case rename
    case moveToTrash
    case deletePermanently
}

struct KeyBinding {
    enum Key {
        /// Физическая клавиша (kVK_*), модификаторы сравниваются точно.
        case code(Int)
        /// Символ; Shift не учитывается, потому что `+` и `*` на многих раскладках набираются с Shift.
        case character(String)
    }

    let key: Key
    let modifiers: NSEvent.ModifierFlags
    let command: PanelCommand

    init(_ key: Key, _ modifiers: NSEvent.ModifierFlags, _ command: PanelCommand) {
        self.key = key
        self.modifiers = modifiers
        self.command = command
    }

    init(_ key: Key, _ command: PanelCommand) {
        self.init(key, [], command)
    }
}

enum PanelKeyMap {
    static let defaults: [KeyBinding] = [
        KeyBinding(.code(kVK_Return), .open),
        KeyBinding(.code(kVK_ANSI_KeypadEnter), .open),
        KeyBinding(.code(kVK_DownArrow), .command, .open),
        KeyBinding(.code(kVK_Delete), .goUp),
        KeyBinding(.code(kVK_UpArrow), .command, .goUp),
        KeyBinding(.code(kVK_Tab), .switchPanel),
        KeyBinding(.code(kVK_Tab), .shift, .switchPanel),
        KeyBinding(.code(kVK_Tab), .control, .nextTab),
        KeyBinding(.code(kVK_Tab), [.control, .shift], .previousTab),

        KeyBinding(.code(kVK_Space), .toggleMark),
        KeyBinding(.code(kVK_Help), .toggleMark), // Insert на PC-клавиатуре
        KeyBinding(.code(kVK_UpArrow), .shift, .invertMovingUp),
        KeyBinding(.code(kVK_DownArrow), .shift, .invertMovingDown),
        KeyBinding(.character("+"), .markByMask),
        KeyBinding(.character("-"), .unmarkByMask),
        KeyBinding(.character("*"), .invertMarks),

        KeyBinding(.code(kVK_F3), .quickLook),
        KeyBinding(.code(kVK_Escape), .closePreview),
        KeyBinding(.code(kVK_F5), .copyToOtherPanel),
        KeyBinding(.code(kVK_F6), .moveToOtherPanel),
        KeyBinding(.code(kVK_F6), .shift, .rename),
        KeyBinding(.code(kVK_F2), .rename),
        KeyBinding(.code(kVK_F7), .makeDirectory),
        KeyBinding(.code(kVK_F8), .moveToTrash),
        KeyBinding(.code(kVK_ForwardDelete), .moveToTrash),
        KeyBinding(.code(kVK_F8), .shift, .deletePermanently),
        KeyBinding(.code(kVK_ForwardDelete), .shift, .deletePermanently),
        // ⌘⌫ и ⌥⌘⌫ — через меню «Файл», как в Finder.
    ]

    static func command(for event: NSEvent, bindings: [KeyBinding] = defaults) -> PanelCommand? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        let character = event.charactersIgnoringModifiers

        for binding in bindings {
            switch binding.key {
            case .code(let code):
                if Int(event.keyCode) == code, modifiers == binding.modifiers {
                    return binding.command
                }
            case .character(let expected):
                if character == expected, modifiers.subtracting(.shift) == binding.modifiers {
                    return binding.command
                }
            }
        }
        return nil
    }
}
