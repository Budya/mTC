import AppKit

/// Главное меню приложения (без storyboard).
///
/// Клавиши пунктов берутся из `Hotkeys`: сочетание с ⌘ ставится пункту меню, остальные (F5, +, Space…)
/// подписываются в названии — их обрабатывает панель, иначе меню перехватывало бы их в полях ввода.
/// При изменении горячих клавиш меню пересобирается.
enum MainMenu {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = submenu(in: mainMenu, title: "mTC")
        appMenu.addItem(withTitle: "О программе mTC", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Горячие клавиши…", action: #selector(AppDelegate.showHotkeys(_:)), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Показывать в Dock", action: #selector(AppDelegate.toggleShowInDock(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Запускать при входе в систему", action: #selector(AppDelegate.toggleLaunchAtLogin(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Открыть папку настроек", action: #selector(AppDelegate.openDataFolder(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть mTC", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Скрыть остальные", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Показать все", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Выйти из mTC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = submenu(in: mainMenu, title: "Файл")
        fileMenu.addItem(item(.search, #selector(MainWindowController.showSearch(_:)), title: "Поиск файлов…"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(.quickLook, #selector(MainWindowController.quickLook(_:))))
        let openWith = NSMenuItem(title: "Открыть с помощью", action: nil, keyEquivalent: "")
        let openWithMenu = NSMenu(title: "Открыть с помощью")
        openWithMenu.delegate = OpenWithMenuDelegate.shared
        openWith.submenu = openWithMenu
        fileMenu.addItem(openWith)
        fileMenu.addItem(item(.edit, #selector(MainWindowController.editItems(_:))))
        fileMenu.addItem(item(.newFile, #selector(MainWindowController.newFile(_:)), title: "Новый файл…"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(.makeDirectory, #selector(MainWindowController.newDirectory(_:)), title: "Новая папка…"))
        fileMenu.addItem(item(.copyToOtherPanel, #selector(MainWindowController.copyToOtherPanel(_:)), title: "Копировать в другую панель…"))
        fileMenu.addItem(item(.moveToOtherPanel, #selector(MainWindowController.moveToOtherPanel(_:)), title: "Переместить в другую панель…"))
        fileMenu.addItem(item(.rename, #selector(MainWindowController.renameItem(_:))))
        fileMenu.addItem(item(.createArchive, #selector(MainWindowController.packItems(_:)), title: "Упаковать…"))
        fileMenu.addItem(item(.extractArchive, #selector(MainWindowController.extractArchives(_:))))
        fileMenu.addItem(item(.moveToTrash, #selector(MainWindowController.moveToTrash(_:)), title: "Переместить в Корзину"))
        fileMenu.addItem(item(.deletePermanently, #selector(MainWindowController.deletePermanently(_:)), title: "Удалить насовсем…"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(.newTab, #selector(MainWindowController.newTab(_:))))
        fileMenu.addItem(item(.closeTab, #selector(MainWindowController.closeTab(_:))))
        fileMenu.addItem(withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            .keyEquivalentModifierMask = [.command, .shift]

        // Стандартные пункты для полей ввода. «Выделить всё» в панели выполняет команду, назначенную на ⌘A.
        let editMenu = submenu(in: mainMenu, title: "Правка")
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выделить всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let markMenu = submenu(in: mainMenu, title: "Выделение")
        markMenu.addItem(item(.markByMask, #selector(MainWindowController.markByMask(_:)), title: "Выделить по маске…"))
        markMenu.addItem(item(.unmarkByMask, #selector(MainWindowController.unmarkByMask(_:)), title: "Снять выделение по маске…"))
        markMenu.addItem(item(.invertMarks, #selector(MainWindowController.invertMarks(_:))))
        markMenu.addItem(.separator())
        markMenu.addItem(item(.markAll, #selector(MainWindowController.markAll(_:))))
        markMenu.addItem(item(.unmarkAll, #selector(MainWindowController.unmarkAll(_:))))
        markMenu.addItem(.separator())
        markMenu.addItem(item(.compareDirectories, #selector(MainWindowController.compareDirectories(_:)), title: "Сравнить папки"))

        let goMenu = submenu(in: mainMenu, title: "Переход")
        goMenu.addItem(item(.goBack, #selector(MainWindowController.goBack(_:))))
        goMenu.addItem(item(.goForward, #selector(MainWindowController.goForward(_:))))
        goMenu.addItem(item(.goUp, #selector(MainWindowController.goUp(_:)), title: "Вверх"))
        goMenu.addItem(.separator())
        goMenu.addItem(item(.goHome, #selector(MainWindowController.goHome(_:)), title: "Домой"))
        goMenu.addItem(item(.goToVolumeRoot, #selector(MainWindowController.goToVolumeRoot(_:))))
        goMenu.addItem(item(.goToOppositeDirectory, #selector(MainWindowController.goToOppositeDirectory(_:))))
        goMenu.addItem(.separator())
        goMenu.addItem(item(.editPath, #selector(MainWindowController.editPath(_:)), title: "Ввести путь…"))

        let viewMenu = submenu(in: mainMenu, title: "Вид")
        viewMenu.addItem(item(.toggleHiddenFiles, #selector(MainWindowController.toggleHiddenFiles(_:)), title: "Показывать скрытые файлы"))
        viewMenu.addItem(item(.refresh, #selector(MainWindowController.refreshPanels(_:))))
        viewMenu.addItem(.separator())
        let themeMenu = submenu(in: viewMenu, title: "Тема")
        for theme in AppTheme.allCases {
            let themeItem = NSMenuItem(title: theme.title, action: #selector(AppDelegate.selectTheme(_:)), keyEquivalent: "")
            themeItem.representedObject = theme.rawValue
            themeMenu.addItem(themeItem)
        }

        let windowMenu = submenu(in: mainMenu, title: "Окно")
        windowMenu.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Изменить масштаб", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(.nextTab, #selector(MainWindowController.nextTab(_:))))
        windowMenu.addItem(item(.previousTab, #selector(MainWindowController.previousTab(_:))))
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    /// Пункт меню для команды: первое сочетание с ⌘ — клавиша пункта, первое без ⌘ — подсказка в названии.
    private static func item(_ command: PanelCommand, _ action: Selector, title: String? = nil) -> NSMenuItem {
        let combos = Hotkeys.shared.combos(for: command)
        var text = title ?? CommandCatalog.info(command).title
        let menuCombo = combos.first { $0.menuKeyEquivalent != nil }
        if let hint = combos.first(where: { $0.menuKeyEquivalent == nil }) {
            text += "  (\(hint.displayString))"
        }
        let item = NSMenuItem(title: text, action: action, keyEquivalent: "")
        if let equivalent = menuCombo?.menuKeyEquivalent {
            item.keyEquivalent = equivalent.key
            item.keyEquivalentModifierMask = equivalent.mask
        }
        return item
    }

    private static func submenu(in menu: NSMenu, title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }
}

/// Строит «Открыть с помощью» в главном меню в момент открытия — для файлов активной панели.
final class OpenWithMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = OpenWithMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        let controller = NSApp.windows.lazy.compactMap { $0.windowController as? MainWindowController }.first
        if let controller {
            controller.populateOpenWithMenu(menu)
        } else {
            menu.removeAllItems()
        }
    }
}
