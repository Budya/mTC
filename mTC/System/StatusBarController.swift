import AppKit

/// Иконка mTC в строке меню.
final class StatusBarController {
    private let statusItem: NSStatusItem

    init(target: AppDelegate, hotKey: HotKeySpec?) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = FloppyIcon.menuBarImage()
            button.toolTip = "mTC"
        }

        let menu = NSMenu()

        let show = NSMenuItem(title: "Показать mTC", action: #selector(AppDelegate.showMainWindow(_:)), keyEquivalent: "")
        if let hotKey, hotKey.enabled {
            show.keyEquivalent = hotKey.menuKeyEquivalent
            show.keyEquivalentModifierMask = hotKey.menuModifierMask
        }
        menu.addItem(show)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Показывать в Dock", action: #selector(AppDelegate.toggleShowInDock(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Запускать при входе в систему", action: #selector(AppDelegate.toggleLaunchAtLogin(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Открыть папку настроек", action: #selector(AppDelegate.openDataFolder(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти из mTC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = target
        }
        statusItem.menu = menu
    }
}
