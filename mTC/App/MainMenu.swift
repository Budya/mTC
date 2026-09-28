import AppKit

/// Главное меню приложения (без storyboard).
enum MainMenu {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = submenu(in: mainMenu, title: "mTC")
        appMenu.addItem(withTitle: "О программе mTC", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
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
        fileMenu.addItem(withTitle: "Просмотр  (F3)", action: #selector(MainWindowController.quickLook(_:)), keyEquivalent: "y")
        let openWith = NSMenuItem(title: "Открыть с помощью", action: nil, keyEquivalent: "")
        let openWithMenu = NSMenu(title: "Открыть с помощью")
        openWithMenu.delegate = OpenWithMenuDelegate.shared
        openWith.submenu = openWithMenu
        fileMenu.addItem(openWith)
        fileMenu.addItem(withTitle: "Редактировать  (F4)", action: #selector(MainWindowController.editItems(_:)), keyEquivalent: "e")
        fileMenu.addItem(withTitle: "Новый файл…  (⇧F4)", action: #selector(MainWindowController.newFile(_:)), keyEquivalent: "n")
            .keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Новая папка…  (F7)", action: #selector(MainWindowController.newDirectory(_:)), keyEquivalent: "n")
            .keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Копировать в другую панель…  (F5)", action: #selector(MainWindowController.copyToOtherPanel(_:)), keyEquivalent: "c")
            .keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Переместить в другую панель…  (F6)", action: #selector(MainWindowController.moveToOtherPanel(_:)), keyEquivalent: "m")
            .keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Переименовать  (⇧F6, F2)", action: #selector(MainWindowController.renameItem(_:)), keyEquivalent: "r")
            .keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Переместить в Корзину  (F8)", action: #selector(MainWindowController.moveToTrash(_:)), keyEquivalent: "\u{8}")
        fileMenu.addItem(withTitle: "Удалить насовсем…  (⇧F8)", action: #selector(MainWindowController.deletePermanently(_:)), keyEquivalent: "\u{8}")
            .keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Новая вкладка", action: #selector(MainWindowController.newTab(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Закрыть вкладку", action: #selector(MainWindowController.closeTab(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            .keyEquivalentModifierMask = [.command, .shift]

        let editMenu = submenu(in: mainMenu, title: "Правка")
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выделить всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Клавиши +, −, * и Space обрабатывает сама панель. Если назначить их пунктам меню,
        // меню перехватит их и в полях ввода, поэтому здесь они только подписаны в названиях.
        let markMenu = submenu(in: mainMenu, title: "Выделение")
        markMenu.addItem(withTitle: "Выделить по маске…  (+)", action: #selector(MainWindowController.markByMask(_:)), keyEquivalent: "")
        markMenu.addItem(withTitle: "Снять выделение по маске…  (−)", action: #selector(MainWindowController.unmarkByMask(_:)), keyEquivalent: "")
        markMenu.addItem(withTitle: "Инвертировать выделение  (*)", action: #selector(MainWindowController.invertMarks(_:)), keyEquivalent: "")
        markMenu.addItem(.separator())
        markMenu.addItem(withTitle: "Выделить всё", action: #selector(MainWindowController.markAll(_:)), keyEquivalent: "")
        markMenu.addItem(withTitle: "Снять всё выделение", action: #selector(MainWindowController.unmarkAll(_:)), keyEquivalent: "a")
            .keyEquivalentModifierMask = [.command, .shift]

        // Стрелки не назначаем пунктам меню: иначе меню перехватит ⌘↑ и т.п. в полях ввода.
        let goMenu = submenu(in: mainMenu, title: "Переход")
        goMenu.addItem(withTitle: "Назад", action: #selector(MainWindowController.goBack(_:)), keyEquivalent: "[")
        goMenu.addItem(withTitle: "Вперёд", action: #selector(MainWindowController.goForward(_:)), keyEquivalent: "]")
        goMenu.addItem(withTitle: "Вверх  (⌘↑, ⌫)", action: #selector(MainWindowController.goUp(_:)), keyEquivalent: "")
        goMenu.addItem(.separator())
        goMenu.addItem(withTitle: "Домой", action: #selector(MainWindowController.goHome(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .shift]
        goMenu.addItem(withTitle: "Корень диска  (⌘⇧↑)", action: #selector(MainWindowController.goToVolumeRoot(_:)), keyEquivalent: "")
        goMenu.addItem(withTitle: "Папка другой панели", action: #selector(MainWindowController.goToOppositeDirectory(_:)), keyEquivalent: "\\")
        goMenu.addItem(.separator())
        goMenu.addItem(withTitle: "Ввести путь…", action: #selector(MainWindowController.editPath(_:)), keyEquivalent: "l")

        let viewMenu = submenu(in: mainMenu, title: "Вид")
        // «>» уже означает Shift+«.», поэтому модификатор только ⌘ (как «}» для ⌘⇧]).
        viewMenu.addItem(withTitle: "Показывать скрытые файлы", action: #selector(MainWindowController.toggleHiddenFiles(_:)), keyEquivalent: ">")
        viewMenu.addItem(withTitle: "Обновить", action: #selector(MainWindowController.refreshPanels(_:)), keyEquivalent: "r")

        let windowMenu = submenu(in: mainMenu, title: "Окно")
        windowMenu.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Изменить масштаб", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        // Как в Safari/Finder: символ «}» уже подразумевает Shift, поэтому модификатор только ⌘.
        windowMenu.addItem(withTitle: "Следующая вкладка  (⌃Tab)", action: #selector(MainWindowController.nextTab(_:)), keyEquivalent: "}")
        windowMenu.addItem(withTitle: "Предыдущая вкладка  (⌃⇧Tab)", action: #selector(MainWindowController.previousTab(_:)), keyEquivalent: "{")
        NSApp.windowsMenu = windowMenu

        return mainMenu
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
