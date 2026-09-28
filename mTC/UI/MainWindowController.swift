import AppKit

/// Главное окно с двумя панелями.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate, NSMenuItemValidation {
    let settings: JSONStore<AppSettings>
    let state: JSONStore<AppState>
    private let splitView = NSSplitView()
    private let leftSide: PanelSideViewController
    private let rightSide: PanelSideViewController
    private var leftPanel: FilePanelViewController { leftSide.panel }
    private var rightPanel: FilePanelViewController { rightSide.panel }
    private var activeSide: PanelSide
    private var didRestoreSplit = false
    /// Кнопка-переключатель скрытых файлов справа на панели F-кнопок.
    private let hiddenFilesButton = NSButton()
    private var keyBar: FunctionKeyBar!

    init(settings: JSONStore<AppSettings>, state: JSONStore<AppState>) {
        self.settings = settings
        self.state = state
        activeSide = state.value.activePanel

        let home = FileManager.default.homeDirectoryForCurrentUser
        let showHidden = settings.value.showHiddenFiles
        leftSide = PanelSideViewController(panel: FilePanelViewController(side: .left, directory: home, showHiddenFiles: showHidden))
        rightSide = PanelSideViewController(panel: FilePanelViewController(side: .right, directory: home, showHiddenFiles: showHidden))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "mTC"
        window.minSize = NSSize(width: 600, height: 350)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed

        super.init(window: window)
        window.delegate = self

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.addArrangedSubview(leftSide.view)
        splitView.addArrangedSubview(rightSide.view)

        keyBar = FunctionKeyBar(keys: [
            .init(command: .quickLook, title: "Просмотр", action: #selector(quickLook(_:))),
            .init(command: .edit, title: "Правка", action: #selector(editItems(_:))),
            .init(command: .copyToOtherPanel, title: "Копировать", action: #selector(copyToOtherPanel(_:))),
            .init(command: .moveToOtherPanel, title: "Переместить", action: #selector(moveToOtherPanel(_:))),
            .init(command: .makeDirectory, title: "Новая папка", action: #selector(newDirectory(_:))),
            .init(command: .moveToTrash, title: "Удалить", action: #selector(moveToTrash(_:))),
        ], target: self, accessories: [hiddenFilesButton])

        let content = NSStackView(views: [splitView, keyBar!])
        content.orientation = .vertical
        content.spacing = 0
        content.distribution = .fill
        for subview in [splitView, keyBar!] {
            subview.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        splitView.setContentHuggingPriority(.defaultLow, for: .vertical)
        keyBar!.setContentHuggingPriority(.required, for: .vertical)
        window.contentView = content

        for side in [leftSide, rightSide] {
            side.panel.delegate = self
            side.onTabsChanged = { [weak self, weak side] in
                guard let self, let side else { return }
                self.saveTabs(of: side)
            }
        }

        hiddenFilesButton.setButtonType(.pushOnPushOff)
        hiddenFilesButton.bezelStyle = .flexiblePush
        hiddenFilesButton.controlSize = .small
        hiddenFilesButton.refusesFirstResponder = true
        hiddenFilesButton.target = self
        hiddenFilesButton.action = #selector(toggleHiddenFiles(_:))
        hiddenFilesButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        updateHiddenFilesButton()
        NotificationCenter.default.addObserver(forName: Hotkeys.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.keyBar.refreshTitles()
        }

        restoreFrame()
        leftSide.restore(state.value.leftTabs, legacyPath: state.value.leftPath)
        rightSide.restore(state.value.rightTabs, legacyPath: state.value.rightPath)
        updateActivePanels()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if !didRestoreSplit {
            splitView.layoutSubtreeIfNeeded()
            let available = splitView.bounds.width - splitView.dividerThickness
            splitView.setPosition(available * min(max(state.value.splitRatio, 0.1), 0.9), ofDividerAt: 0)
            didRestoreSplit = true
        }
        panel(for: activeSide).focus()
    }

    /// Кнопка на панели, «Вид → Показывать скрытые файлы», ⌘⇧.
    @objc func toggleHiddenFiles(_ sender: Any?) {
        settings.update { $0.showHiddenFiles.toggle() }
        let show = settings.value.showHiddenFiles
        leftPanel.showHiddenFiles = show
        rightPanel.showHiddenFiles = show
        updateHiddenFilesButton()
        panel(for: activeSide).focus()
    }

    private func updateHiddenFilesButton() {
        let show = settings.value.showHiddenFiles
        hiddenFilesButton.state = show ? .on : .off
        hiddenFilesButton.image = NSImage(
            systemSymbolName: show ? "eye" : "eye.slash",
            accessibilityDescription: show ? "Скрытые файлы показаны" : "Скрытые файлы скрыты"
        )
        hiddenFilesButton.toolTip = (show ? "Скрыть скрытые файлы" : "Показать скрытые файлы") + " (⌘⇧.)"
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleHiddenFiles(_:)) {
            menuItem.state = settings.value.showHiddenFiles ? .on : .off
        }
        return true
    }

    @objc func refreshPanels(_ sender: Any?) {
        leftPanel.reload()
        rightPanel.reload()
    }

    @objc func markByMask(_ sender: Any?) {
        panel(for: activeSide).perform(.markByMask)
    }

    @objc func unmarkByMask(_ sender: Any?) {
        panel(for: activeSide).perform(.unmarkByMask)
    }

    @objc func invertMarks(_ sender: Any?) {
        panel(for: activeSide).perform(.invertMarks)
    }

    @objc func markAll(_ sender: Any?) {
        panel(for: activeSide).perform(.markAll)
    }

    @objc func unmarkAll(_ sender: Any?) {
        panel(for: activeSide).perform(.unmarkAll)
    }

    /// F7 / ⌘⇧N: новая папка в активной панели.
    @objc func newDirectory(_ sender: Any?) {
        filePanelRequestsNewDirectory(panel(for: activeSide))
    }

    // MARK: Переход

    @objc func goBack(_ sender: Any?) { panel(for: activeSide).perform(.goBack) }
    @objc func goForward(_ sender: Any?) { panel(for: activeSide).perform(.goForward) }
    @objc func goUp(_ sender: Any?) { panel(for: activeSide).perform(.goUp) }
    @objc func goHome(_ sender: Any?) { panel(for: activeSide).perform(.goHome) }
    @objc func goToVolumeRoot(_ sender: Any?) { panel(for: activeSide).perform(.goToVolumeRoot) }
    @objc func goToOppositeDirectory(_ sender: Any?) { panel(for: activeSide).perform(.goToOppositeDirectory) }
    @objc func editPath(_ sender: Any?) { panel(for: activeSide).perform(.editPath) }

    /// F3 / ⌘Y: просмотр (Quick Look).
    @objc func quickLook(_ sender: Any?) {
        panel(for: activeSide).perform(.quickLook)
    }

    /// Меню «Файл → Открыть с помощью» строится при открытии — для файлов активной панели.
    func populateOpenWithMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let panel = panel(for: activeSide)
        let targets = panel.operationTargets()
        if targets.isEmpty {
            let none = NSMenuItem(title: "Нет выбранных файлов", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            panel.openWithItems(for: targets).forEach(menu.addItem)
        }
    }

    /// F4 / ⌘E: открыть в редакторе.
    @objc func editItems(_ sender: Any?) {
        let panel = panel(for: activeSide)
        filePanel(panel, requestsEditOf: panel.operationTargets())
    }

    /// ⇧F4 / ⌥⌘N: новый файл.
    @objc func newFile(_ sender: Any?) {
        filePanelRequestsNewFile(panel(for: activeSide))
    }

    /// F5 / ⌘⇧C: копировать в другую панель.
    @objc func copyToOtherPanel(_ sender: Any?) {
        let panel = panel(for: activeSide)
        filePanel(panel, requestsCopyOf: panel.operationTargets())
    }

    /// F6 / ⌘⇧M: переместить в другую панель.
    @objc func moveToOtherPanel(_ sender: Any?) {
        let panel = panel(for: activeSide)
        filePanel(panel, requestsMoveOf: panel.operationTargets())
    }

    /// ⇧F6 / F2 / ⌘⇧R: переименовать файл под курсором прямо в списке.
    @objc func renameItem(_ sender: Any?) {
        panel(for: activeSide).beginRename()
    }

    /// ⌥F5: упаковать выбранное в архив.
    @objc func packItems(_ sender: Any?) {
        let panel = panel(for: activeSide)
        filePanel(panel, requestsPackOf: panel.operationTargets())
    }

    /// ⌥F9: распаковать выбранные архивы в текущую папку.
    @objc func extractArchives(_ sender: Any?) {
        let panel = panel(for: activeSide)
        filePanel(panel, requestsExtractOf: panel.operationTargets())
    }

    /// F8 / ⌘⌫: в Корзину.
    @objc func moveToTrash(_ sender: Any?) {
        let panel = panel(for: activeSide)
        filePanel(panel, requestsDeletionOf: panel.operationTargets(), permanently: false)
    }

    /// ⇧F8 / ⌥⌘⌫: удалить насовсем.
    @objc func deletePermanently(_ sender: Any?) {
        let panel = panel(for: activeSide)
        filePanel(panel, requestsDeletionOf: panel.operationTargets(), permanently: true)
    }

    @objc func newTab(_ sender: Any?) {
        side(for: activeSide).newTab()
    }

    /// ⌘W: закрыть вкладку, а если она последняя — окно.
    @objc func closeTab(_ sender: Any?) {
        let side = side(for: activeSide)
        if !side.closeTab(at: side.activeIndex) {
            window?.performClose(sender)
        }
    }

    @objc func nextTab(_ sender: Any?) {
        side(for: activeSide).selectTab(offset: 1)
    }

    @objc func previousTab(_ sender: Any?) {
        side(for: activeSide).selectTab(offset: -1)
    }

    /// Сохраняет всё, что относится к окну (вызывается перед выходом).
    func saveState() {
        guard let window else { return }
        state.update {
            $0.windowFrame = WindowFrame(window.frame)
            $0.leftTabs = leftSide.saved
            $0.rightTabs = rightSide.saved
            $0.leftPath = nil
            $0.rightPath = nil
            $0.activePanel = activeSide
        }
    }

    // MARK: - Восстановление

    private func restoreFrame() {
        guard let window else { return }
        if let frame = state.value.windowFrame?.rect,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
    }

    private func saveTabs(of side: PanelSideViewController) {
        let saved = side.saved
        state.update {
            if side === leftSide { $0.leftTabs = saved } else { $0.rightTabs = saved }
        }
    }

    private func side(for side: PanelSide) -> PanelSideViewController {
        side == .left ? leftSide : rightSide
    }

    private func panel(for side: PanelSide) -> FilePanelViewController {
        self.side(for: side).panel
    }

    func oppositePanel(of panel: FilePanelViewController) -> FilePanelViewController {
        self.panel(for: panel.side.opposite)
    }

    private func updateActivePanels() {
        leftSide.isActive = activeSide == .left
        rightSide.isActive = activeSide == .right
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    private func saveFrame() {
        guard let window else { return }
        let frame = WindowFrame(window.frame)
        if state.value.windowFrame != frame {
            state.update { $0.windowFrame = frame }
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard didRestoreSplit else { return }
        let available = splitView.bounds.width - splitView.dividerThickness
        guard available > 0 else { return }
        let ratio = (leftSide.view.frame.width / available * 1000).rounded() / 1000
        if state.value.splitRatio != ratio {
            state.update { $0.splitRatio = ratio }
        }
    }
}

// MARK: - FilePanelDelegate

extension MainWindowController: FilePanelDelegate {
    func filePanelDidBecomeActive(_ panel: FilePanelViewController) {
        guard activeSide != panel.side else { return }
        activeSide = panel.side
        updateActivePanels()
        state.update { $0.activePanel = panel.side }
    }

    func filePanelDidChangeDirectory(_ panel: FilePanelViewController) {
        side(for: panel.side).panelDidChangeDirectory()
    }

    func filePanel(_ panel: FilePanelViewController, requestsTabOffset offset: Int) {
        side(for: panel.side).selectTab(offset: offset)
    }

    func filePanel(_ panel: FilePanelViewController, requestsNewTabWith directory: URL) {
        side(for: panel.side).newTab(directory: directory)
    }

    func filePanel(_ panel: FilePanelViewController, performWindowCommand command: PanelCommand) {
        switch command {
        case .refresh: refreshPanels(nil)
        case .toggleHiddenFiles: toggleHiddenFiles(nil)
        case .newTab: newTab(nil)
        case .closeTab: closeTab(nil)
        default: break
        }
    }

    func filePanelOppositeDirectory(_ panel: FilePanelViewController) -> URL? {
        oppositePanel(of: panel).directory
    }

    func filePanelRequestsNewDirectory(_ panel: FilePanelViewController) {
        guard let window else { return }
        TextPrompt.present(
            on: window,
            title: "Новая папка",
            message: "В «\(panel.directory.lastPathComponent)». Можно сразу создать вложенные: папка/подпапка",
            defaultValue: FileOperations.uniqueURL(for: panel.directory.appendingPathComponent("Новая папка")).lastPathComponent,
            okTitle: "Создать"
        ) { name in
            if let name { panel.createDirectory(named: name) }
            panel.focus()
        }
    }

    func filePanelRequestsFocusSwitch(_ panel: FilePanelViewController) {
        self.panel(for: panel.side.opposite).focus()
    }

    func filePanel(_ panel: FilePanelViewController, requestsMaskForMarking marking: Bool) {
        guard let window, window.attachedSheet == nil else { return }

        let alert = NSAlert()
        alert.messageText = marking ? "Выделить по маске" : "Снять выделение по маске"
        alert.informativeText = "Несколько масок — через «;», например: *.jpg;*.png"

        let field = NSTextField(string: state.value.lastSelectionMask)
        field.placeholderString = "*"
        let includeDirectories = NSButton(checkboxWithTitle: "Включая папки", target: nil, action: nil)
        includeDirectories.state = state.value.maskIncludesDirectories ? .on : .off

        let stack = NSStackView(views: [field, includeDirectories])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 52)
        field.widthAnchor.constraint(equalToConstant: 280).isActive = true
        alert.accessoryView = stack

        alert.addButton(withTitle: marking ? "Выделить" : "Снять")
        alert.addCancelButton()
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { [weak self] response in
            defer { panel.focus() }
            guard let self, response == .alertFirstButtonReturn else { return }
            let mask = field.stringValue.trimmingCharacters(in: .whitespaces)
            let withDirectories = includeDirectories.state == .on
            self.state.update {
                $0.lastSelectionMask = mask.isEmpty ? "*" : mask
                $0.maskIncludesDirectories = withDirectories
            }
            panel.mark(matching: FileMask(mask.isEmpty ? "*" : mask), includeDirectories: withDirectories, marking: marking)
        }
    }
}

// MARK: - Удаление

extension MainWindowController {
    func filePanel(_ panel: FilePanelViewController, requestsDeletionOf targets: [FileItem], permanently: Bool) {
        guard let window, window.attachedSheet == nil, !targets.isEmpty else { return }
        let urls = targets.map(\.url)

        if !permanently && !settings.value.confirmMoveToTrash {
            runDeletion(urls, permanently: false, from: panel)
            return
        }

        let alert = NSAlert()
        alert.messageText = permanently ? "Удалить насовсем?" : "Переместить в Корзину?"
        alert.informativeText = Self.describe(targets) + (permanently ? "\n\nЭто действие нельзя отменить." : "")
        alert.alertStyle = permanently ? .critical : .informational
        let confirm = alert.addButton(withTitle: permanently ? "Удалить насовсем" : "В Корзину")
        confirm.hasDestructiveAction = permanently
        alert.addCancelButton()
        if !permanently {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Больше не спрашивать"
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn else {
                panel.focus()
                return
            }
            if alert.suppressionButton?.state == .on {
                self.settings.update { $0.confirmMoveToTrash = false }
            }
            self.runDeletion(urls, permanently: permanently, from: panel)
        }
    }

    private func runDeletion(_ urls: [URL], permanently: Bool, from panel: FilePanelViewController) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = permanently ? FileOperations.deletePermanently(urls) : FileOperations.moveToTrash(urls)
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshPanels(nil)
                panel.focus()
                if !result.trashUnavailable.isEmpty {
                    self.offerPermanentDeletion(result.trashUnavailable, from: panel, failures: result.failures)
                } else {
                    self.reportFailures(result.failures)
                }
            }
        }
    }

    /// На томе нет Корзины (сетевой диск и т.п.) — предлагаем удалить эти объекты насовсем.
    private func offerPermanentDeletion(_ urls: [URL], from panel: FilePanelViewController, failures: [(url: URL, error: Error)]) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Корзина здесь недоступна"
        alert.informativeText = "На этом диске нет Корзины (например, это сетевой диск). Удалить насовсем?\n\n"
            + Self.describe(urls.map(\.lastPathComponent)) + "\n\nЭто действие нельзя отменить."
        alert.addButton(withTitle: "Удалить насовсем").hasDestructiveAction = true
        alert.addCancelButton()
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                self.runDeletion(urls, permanently: true, from: panel)
            } else {
                panel.focus()
            }
            self.reportFailures(failures)
        }
    }

    func reportFailures(_ failures: [(url: URL, error: Error)], verb: String = "удалить") {
        guard !failures.isEmpty, let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failures.count == 1 ? "Не удалось \(verb) «\(failures[0].url.lastPathComponent)»" : "Не удалось \(verb) \(failures.count) объектов"
        alert.informativeText = failures.prefix(10)
            .map { "«\($0.url.lastPathComponent)»: \($0.error.localizedDescription)" }
            .joined(separator: "\n") + (failures.count > 10 ? "\n… и ещё \(failures.count - 10)" : "")
        if window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static func describe(_ items: [FileItem]) -> String {
        if items.count == 1, let item = items.first {
            return "\(item.kind == .directory ? "Папка" : "Файл") «\(item.name)»"
        }
        let directories = items.filter { $0.kind == .directory }.count
        return describe(items.map(\.name)) + " (папок: \(directories), файлов: \(items.count - directories))"
    }

    private static func describe(_ names: [String]) -> String {
        if names.count == 1 { return "«\(names[0])»" }
        let shown = names.prefix(5).map { "«\($0)»" }.joined(separator: ", ")
        return "\(names.count) объектов: \(shown)" + (names.count > 5 ? " и ещё \(names.count - 5)" : "")
    }
}
