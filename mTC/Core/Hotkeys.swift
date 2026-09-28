import AppKit

/// Команда в списке горячих клавиш: название, раздел и сочетания по умолчанию.
struct CommandInfo {
    let command: PanelCommand
    let title: String
    let category: String
    let defaults: [String]
}

/// Все команды, которым можно назначить клавиши, в порядке показа в окне «Горячие клавиши».
enum CommandCatalog {
    static let all: [CommandInfo] = [
        CommandInfo(command: .open, title: "Открыть", category: "Навигация", defaults: ["enter", "keypadenter", "cmd+down"]),
        CommandInfo(command: .goUp, title: "На уровень вверх", category: "Навигация", defaults: ["backspace", "cmd+up"]),
        CommandInfo(command: .goBack, title: "Назад", category: "Навигация", defaults: ["cmd+["]),
        CommandInfo(command: .goForward, title: "Вперёд", category: "Навигация", defaults: ["cmd+]"]),
        CommandInfo(command: .goHome, title: "Домашняя папка", category: "Навигация", defaults: ["shift+cmd+h"]),
        CommandInfo(command: .goToVolumeRoot, title: "Корень диска", category: "Навигация", defaults: ["shift+cmd+up"]),
        CommandInfo(command: .goToOppositeDirectory, title: "Папка другой панели", category: "Навигация", defaults: ["cmd+\\"]),
        CommandInfo(command: .editPath, title: "Ввести путь", category: "Навигация", defaults: ["cmd+l"]),
        CommandInfo(command: .switchPanel, title: "Другая панель", category: "Навигация", defaults: ["tab", "shift+tab"]),
        CommandInfo(command: .refresh, title: "Обновить", category: "Навигация", defaults: ["cmd+r"]),

        CommandInfo(command: .newTab, title: "Новая вкладка", category: "Вкладки", defaults: ["cmd+t"]),
        CommandInfo(command: .closeTab, title: "Закрыть вкладку", category: "Вкладки", defaults: ["cmd+w"]),
        CommandInfo(command: .nextTab, title: "Следующая вкладка", category: "Вкладки", defaults: ["ctrl+tab", "shift+cmd+]"]),
        CommandInfo(command: .previousTab, title: "Предыдущая вкладка", category: "Вкладки", defaults: ["ctrl+shift+tab", "shift+cmd+["]),
        CommandInfo(command: .openInNewTab, title: "Открыть папку в новой вкладке", category: "Вкладки", defaults: ["cmd+enter"]),

        CommandInfo(command: .toggleMark, title: "Выделить / снять и вниз", category: "Выделение", defaults: ["space", "insert"]),
        CommandInfo(command: .invertMovingUp, title: "Инвертировать и вверх", category: "Выделение", defaults: ["shift+up"]),
        CommandInfo(command: .invertMovingDown, title: "Инвертировать и вниз", category: "Выделение", defaults: ["shift+down"]),
        CommandInfo(command: .markByMask, title: "Выделить по маске", category: "Выделение", defaults: ["plus"]),
        CommandInfo(command: .unmarkByMask, title: "Снять выделение по маске", category: "Выделение", defaults: ["minus"]),
        CommandInfo(command: .invertMarks, title: "Инвертировать выделение", category: "Выделение", defaults: ["asterisk"]),
        CommandInfo(command: .toggleMarkAll, title: "Выделить всё / снять", category: "Выделение", defaults: ["cmd+a"]),
        CommandInfo(command: .markAll, title: "Выделить всё", category: "Выделение", defaults: []),
        CommandInfo(command: .unmarkAll, title: "Снять всё выделение", category: "Выделение", defaults: ["shift+cmd+a"]),

        CommandInfo(command: .quickLook, title: "Просмотр", category: "Файлы", defaults: ["f3", "cmd+y"]),
        CommandInfo(command: .closePreview, title: "Закрыть просмотр", category: "Файлы", defaults: ["esc"]),
        CommandInfo(command: .edit, title: "Редактировать", category: "Файлы", defaults: ["f4", "cmd+e"]),
        CommandInfo(command: .newFile, title: "Новый файл", category: "Файлы", defaults: ["shift+f4", "alt+cmd+n"]),
        CommandInfo(command: .copyToOtherPanel, title: "Копировать в другую панель", category: "Файлы", defaults: ["f5", "shift+cmd+c"]),
        CommandInfo(command: .moveToOtherPanel, title: "Переместить в другую панель", category: "Файлы", defaults: ["f6", "shift+cmd+m"]),
        CommandInfo(command: .rename, title: "Переименовать", category: "Файлы", defaults: ["shift+f6", "f2", "shift+cmd+r"]),
        CommandInfo(command: .makeDirectory, title: "Новая папка", category: "Файлы", defaults: ["f7", "shift+cmd+n"]),
        CommandInfo(command: .moveToTrash, title: "В Корзину", category: "Файлы", defaults: ["f8", "delete", "cmd+backspace"]),
        CommandInfo(command: .deletePermanently, title: "Удалить насовсем", category: "Файлы", defaults: ["shift+f8", "shift+delete", "alt+cmd+backspace"]),

        CommandInfo(command: .createArchive, title: "Упаковать", category: "Архивы", defaults: ["alt+f5", "alt+cmd+a"]),
        CommandInfo(command: .extractArchive, title: "Распаковать сюда", category: "Архивы", defaults: ["alt+f9", "alt+cmd+x"]),

        CommandInfo(command: .toggleHiddenFiles, title: "Показать / скрыть скрытые файлы", category: "Вид", defaults: ["shift+cmd+."]),

        CommandInfo(command: .showHideWindow, title: "Показать / скрыть mTC из любой программы", category: "Глобальные", defaults: ["ctrl+alt+t"]),
    ]

    static func info(_ command: PanelCommand) -> CommandInfo {
        all.first { $0.command == command } ?? CommandInfo(command: command, title: command.rawValue, category: "", defaults: [])
    }

    /// Сочетания, занятые стандартными пунктами меню (выход, скрыть, вырезать/копировать/вставить…).
    static let reserved: [KeyCombo: String] = {
        let items: [(String, String)] = [
            ("cmd+q", "Выйти из mTC"), ("cmd+h", "Скрыть mTC"), ("alt+cmd+h", "Скрыть остальные"),
            ("cmd+m", "Свернуть"), ("cmd+x", "Вырезать"), ("cmd+c", "Копировать"), ("cmd+v", "Вставить"),
            ("shift+cmd+w", "Закрыть окно"),
        ]
        var result: [KeyCombo: String] = [:]
        for (string, title) in items {
            if let combo = KeyCombo(string: string) { result[combo] = title }
        }
        return result
    }()
}

/// `mTC-data/hotkeys.json`.
struct HotkeysFile: Codable {
    var version = 1
    /// Команда → сочетания: `"copyToOtherPanel": ["f5", "shift+cmd+c"]`.
    var bindings: [String: [String]]

    static var defaults: HotkeysFile {
        HotkeysFile(bindings: Dictionary(uniqueKeysWithValues: CommandCatalog.all.map { ($0.command.rawValue, $0.defaults) }))
    }
}

/// Текущие привязки клавиш: читаются из `hotkeys.json`, меняются в окне «Горячие клавиши».
/// При изменении рассылается `Hotkeys.didChange` — меню, кнопки и глобальная клавиша обновляются.
final class Hotkeys {
    static let didChange = Notification.Name("mTC.hotkeysDidChange")

    /// Общий экземпляр. AppDelegate заменяет его на связанный с `mTC-data/hotkeys.json`.
    static var shared = Hotkeys(fileURL: nil)

    private let store: JSONStore<HotkeysFile>
    private(set) var bindings: [PanelCommand: [KeyCombo]] = [:]
    /// Что не удалось разобрать в файле (показывается при запуске).
    private(set) var problems: [String] = []
    private var lookup: [KeyCombo: PanelCommand] = [:]
    private var characterLookup: [KeyCombo: PanelCommand] = [:]

    init(fileURL: URL?) {
        store = JSONStore(fileURL: fileURL, defaultValue: HotkeysFile.defaults)
        rebuild()
    }

    func combos(for command: PanelCommand) -> [KeyCombo] {
        bindings[command] ?? []
    }

    func command(for combo: KeyCombo) -> PanelCommand? {
        lookup[combo]
    }

    /// Команда для нажатия в панели (глобальная клавиша сюда не попадает — её ловит система).
    func command(for event: NSEvent) -> PanelCommand? {
        if let combo = KeyCombo(event: event), case .code = combo.key, let command = lookup[combo], command != .showHideWindow {
            return command
        }
        for (combo, command) in characterLookup where combo.matches(event) {
            return command
        }
        return nil
    }

    /// Подсказка для меню и кнопок: F-клавиша, если есть, иначе первое сочетание.
    func hint(for command: PanelCommand) -> String? {
        let combos = combos(for: command)
        return (combos.first(where: \.isFunctionKey) ?? combos.first)?.displayString
    }

    func set(_ combos: [KeyCombo], for command: PanelCommand) {
        store.update { $0.bindings[command.rawValue] = combos.map(\.stringValue) }
        store.flush()
        rebuild()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func resetToDefaults(_ command: PanelCommand) {
        let defaults = CommandCatalog.info(command).defaults.compactMap(KeyCombo.init(string:))
        // Сочетания по умолчанию могли быть переназначены другим командам — забираем их обратно.
        for combo in defaults {
            if let other = lookup[combo], other != command {
                store.update { $0.bindings[other.rawValue] = combos(for: other).filter { $0 != combo }.map(\.stringValue) }
            }
        }
        set(defaults, for: command)
    }

    func resetAll() {
        store.update { $0 = HotkeysFile.defaults }
        store.flush()
        rebuild()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func rebuild() {
        var bindings: [PanelCommand: [KeyCombo]] = [:]
        var lookup: [KeyCombo: PanelCommand] = [:]
        var characterLookup: [KeyCombo: PanelCommand] = [:]
        var problems: [String] = []

        let known = Set(CommandCatalog.all.map(\.command.rawValue))
        for name in store.value.bindings.keys where !known.contains(name) {
            problems.append("неизвестная команда «\(name)»")
        }

        for info in CommandCatalog.all {
            let strings = store.value.bindings[info.command.rawValue] ?? info.defaults
            var combos: [KeyCombo] = []
            for string in strings {
                guard let combo = KeyCombo(string: string) else {
                    problems.append("«\(string)» у команды \(info.command.rawValue)")
                    continue
                }
                if let owner = lookup[combo] {
                    problems.append("«\(string)» назначено и «\(CommandCatalog.info(owner).title)», и «\(info.title)»")
                    continue
                }
                combos.append(combo)
                lookup[combo] = info.command
                if case .character = combo.key { characterLookup[combo] = info.command }
            }
            bindings[info.command] = combos
        }

        self.bindings = bindings
        self.lookup = lookup
        self.characterLookup = characterLookup
        self.problems = problems
    }
}
