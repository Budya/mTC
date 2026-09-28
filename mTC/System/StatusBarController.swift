import AppKit

/// Иконка mTC в строке меню.
final class StatusBarController {
    private let statusItem: NSStatusItem

    private weak var target: AppDelegate?

    init(target: AppDelegate) {
        self.target = target
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = FloppyIcon.menuBarImage()
            button.toolTip = "mTC"
        }

        rebuildMenu()
    }

    /// Пересобирает меню (в пункте «Показать mTC» — текущая глобальная клавиша).
    func rebuildMenu() {
        guard let target else { return }
        let menu = NSMenu()

        let show = NSMenuItem(title: "Показать mTC", action: #selector(AppDelegate.showMainWindow(_:)), keyEquivalent: "")
        if let equivalent = Hotkeys.shared.combos(for: .showHideWindow).first?.anyMenuKeyEquivalent {
            show.keyEquivalent = equivalent.key
            show.keyEquivalentModifierMask = equivalent.mask
        }
        menu.addItem(show)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Показывать в Dock", action: #selector(AppDelegate.toggleShowInDock(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Запускать при входе в систему", action: #selector(AppDelegate.toggleLaunchAtLogin(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Открыть папку настроек", action: #selector(AppDelegate.openDataFolder(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Горячие клавиши…", action: #selector(AppDelegate.showHotkeys(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти из mTC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = target
        }
        statusItem.menu = menu
    }
}
