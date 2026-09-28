import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Просьба уже запущенной копии (той же `.app`) показать окно.
    private static let showWindowNotification = Notification.Name("dev.mtc.mTC.showWindow")

    private var dataLocation: DataLocation!
    private var instanceLock: InstanceLock?
    private var settings: JSONStore<AppSettings>!
    private var state: JSONStore<AppState>!
    private var mainWindow: MainWindowController!
    private var statusBar: StatusBarController!
    private var hotKey: GlobalHotKey?
    private var hotkeysWindow: HotkeysWindowController?
    private var launchedAsLoginItem = false

    // MARK: - Жизненный цикл

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Не даём AppKit сохранять состояние окон в ~/Library/Saved Application State.
        UserDefaults.standard.register(defaults: [
            "ApplePersistenceIgnoreState": true,
            "NSQuitAlwaysKeepsWindows": false,
        ])
        launchedAsLoginItem = Self.isLaunchedAsLoginItem()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOverToRunningInstance() {
            NSApp.terminate(nil)
            return
        }

        var location = DataLocation.resolve()
        if location.canPersist {
            instanceLock = InstanceLock(directory: location.directory)
            if instanceLock == nil { location.problem = .lockedByAnotherInstance }
        }
        dataLocation = location

        settings = JSONStore(fileURL: location.canPersist ? location.file("settings.json") : nil, defaultValue: AppSettings())
        state = JSONStore(fileURL: location.canPersist ? location.file("state.json") : nil, defaultValue: AppState())
        Hotkeys.shared = Hotkeys(fileURL: location.canPersist ? location.file("hotkeys.json") : nil)

        NSApp.mainMenu = MainMenu.build()
        applyDockPolicy()
        statusBar = StatusBarController(target: self)
        mainWindow = MainWindowController(settings: settings, state: state)
        registerGlobalHotKey()
        refreshLoginItemIfMoved()
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeysDidChange), name: Hotkeys.didChange, object: nil)

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowWindowRequest(_:)),
            name: Self.showWindowNotification,
            object: Bundle.main.bundlePath
        )

        if location.problem != nil || (settings.value.showWindowAtLaunch && !launchedAsLoginItem) {
            showMainWindow(nil)
        }
        if !Hotkeys.shared.problems.isEmpty {
            reportHotkeyProblems(Hotkeys.shared.problems)
        }
        if let problem = location.problem, !presentDataLocationProblem(problem) {
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindow?.saveState()
        settings?.flush()
        state?.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow(nil) }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Действия

    @objc func showMainWindow(_ sender: Any?) {
        NSApp.unhide(nil)
        mainWindow.showWindow(nil)
        mainWindow.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc func toggleMainWindow(_ sender: Any?) {
        if NSApp.isActive, mainWindow.window?.isVisible == true {
            NSApp.hide(nil)
        } else {
            showMainWindow(nil)
        }
    }

    @objc func toggleShowInDock(_ sender: Any?) {
        settings.update { $0.showInDock.toggle() }
        applyDockPolicy()
        if mainWindow.window?.isVisible == true {
            showMainWindow(nil)
        }
    }

    @objc func toggleHiddenFiles(_ sender: Any?) {
        mainWindow.toggleHiddenFiles(sender)
    }

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        do {
            if LoginItem.isEnabled {
                try LoginItem.disable()
                state.update { $0.loginItemAppPath = nil }
            } else {
                try LoginItem.enable()
                state.update { $0.loginItemAppPath = Bundle.main.bundlePath }
                if LoginItem.status == .requiresApproval {
                    LoginItem.openSystemSettings()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Не удалось изменить автозагрузку"
            alert.informativeText = "\(error.localizedDescription)\n\nmTC можно добавить вручную: Системные настройки → Основные → Объекты входа."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Открыть настройки")
            if alert.runModal() == .alertSecondButtonReturn {
                LoginItem.openSystemSettings()
            }
        }
    }

    @objc func openDataFolder(_ sender: Any?) {
        NSWorkspace.shared.open(dataLocation.directory)
    }

    @objc private func handleShowWindowRequest(_ notification: Notification) {
        showMainWindow(nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleShowInDock(_:)):
            menuItem.state = settings.value.showInDock ? .on : .off
        case #selector(toggleHiddenFiles(_:)):
            menuItem.state = settings.value.showHiddenFiles ? .on : .off
        case #selector(toggleLaunchAtLogin(_:)):
            menuItem.state = LoginItem.isEnabled ? .on : .off
            if case .translocated = dataLocation.problem { return false }
        case #selector(openDataFolder(_:)):
            return FileManager.default.fileExists(atPath: dataLocation.directory.path)
        default:
            break
        }
        return true
    }

    // MARK: - Внутреннее

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(settings.value.showInDock ? .regular : .accessory)
    }

    /// Глобальная клавиша «показать/скрыть mTC» — из `hotkeys.json` (команда showHideWindow).
    private func registerGlobalHotKey() {
        hotKey = nil
        guard let combo = Hotkeys.shared.combos(for: .showHideWindow).first, let keyCode = combo.carbonKeyCode else { return }
        hotKey = GlobalHotKey(keyCode: keyCode, modifiers: combo.carbonModifiers) { [weak self] in
            self?.toggleMainWindow(nil)
        }
        if hotKey == nil {
            NSLog("mTC: не удалось зарегистрировать глобальную клавишу \(combo.displayString) (возможно, она занята другим приложением)")
        }
    }

    @objc private func hotkeysDidChange() {
        NSApp.mainMenu = MainMenu.build()
        statusBar.rebuildMenu()
        registerGlobalHotKey()
    }

    @objc func showHotkeys(_ sender: Any?) {
        if hotkeysWindow == nil {
            hotkeysWindow = HotkeysWindowController(hotkeys: Hotkeys.shared)
        }
        hotkeysWindow?.showWindow(nil)
        hotkeysWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func reportHotkeyProblems(_ problems: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "В hotkeys.json есть ошибки"
        alert.informativeText = problems.prefix(10).map { "• " + $0 }.joined(separator: "\n")
            + (problems.count > 10 ? "\n… и ещё \(problems.count - 10)" : "")
            + "\n\nЭти сочетания не действуют. Исправьте файл или откройте «Горячие клавиши…»."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Горячие клавиши…")
        if alert.runModal() == .alertSecondButtonReturn {
            showHotkeys(nil)
        }
    }

    /// Если папку с mTC перенесли, регистрация автозагрузки указывает на старый путь — обновляем.
    private func refreshLoginItemIfMoved() {
        let currentPath = Bundle.main.bundlePath
        guard dataLocation.canPersist,
              let savedPath = state.value.loginItemAppPath,
              savedPath != currentPath,
              LoginItem.isEnabled else { return }
        try? LoginItem.disable()
        if (try? LoginItem.enable()) != nil {
            state.update { $0.loginItemAppPath = currentPath }
        }
    }

    /// Если эта же `.app` уже запущена — просим её показать окно, а сами выходим.
    private func handOverToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownURL = Bundle.main.bundleURL.standardizedFileURL
        let current = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter {
            $0.processIdentifier != current && $0.bundleURL?.standardizedFileURL == ownURL
        }
        guard !others.isEmpty else { return false }

        DistributedNotificationCenter.default().postNotificationName(
            Self.showWindowNotification,
            object: Bundle.main.bundlePath,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }

    private static func isLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// Возвращает `false`, если пользователь выбрал «Выход».
    private func presentDataLocationProblem(_ problem: DataLocation.Problem) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch problem {
        case .translocated(let originalAppURL):
            let appPath = originalAppURL?.path ?? "/путь/к/mTC.app"
            let command = "xattr -dr com.apple.quarantine \"\(appPath)\""
            alert.messageText = "mTC запущен из карантина macOS"
            alert.informativeText = """
            macOS запустил приложение из временной копии, поэтому папку \(DataLocation.folderName) рядом с ним не найти. \
            Настройки в этом сеансе не сохранятся.

            Выполните в Терминале и перезапустите mTC:
            \(command)
            """
            alert.addButton(withTitle: "Скопировать команду и выйти")
            alert.addButton(withTitle: "Продолжить без сохранения")
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                return false
            }
            return true

        case .notWritable:
            alert.messageText = "Папка настроек недоступна для записи"
            alert.informativeText = "\(dataLocation.directory.path)\n\nmTC будет работать, но настройки не сохранятся."
            alert.addButton(withTitle: "Продолжить")
            alert.addButton(withTitle: "Выход")
            return alert.runModal() == .alertFirstButtonReturn

        case .lockedByAnotherInstance:
            alert.messageText = "Настройки уже используются"
            alert.informativeText = """
            Папку \(dataLocation.directory.path) использует другой запущенный экземпляр mTC \
            (возможно, на другом компьютере). Настройки в этом сеансе не сохранятся.
            """
            alert.addButton(withTitle: "Продолжить без сохранения")
            alert.addButton(withTitle: "Выход")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }
}
