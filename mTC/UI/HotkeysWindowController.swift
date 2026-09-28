import AppKit
import Carbon.HIToolbox

/// Окно «Горячие клавиши»: список команд по разделам, у выбранной — её сочетания
/// (клик по сочетанию удаляет его), «+ Добавить» записывает новое нажатие.
/// Изменения сохраняются в `hotkeys.json` и применяются сразу.
final class HotkeysWindowController: NSWindowController, NSWindowDelegate {
    private enum Row {
        case header(String)
        case command(CommandInfo)
    }

    private let hotkeys: Hotkeys
    private var rows: [Row] = []

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let commandLabel = NSTextField(labelWithString: "")
    private let combosStack = NSStackView()
    private let addButton = NSButton(title: "+ Добавить", target: nil, action: nil)
    private let defaultButton = NSButton(title: "По умолчанию", target: nil, action: nil)
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private let resetAllButton = NSButton(title: "Сбросить все…", target: nil, action: nil)

    private var recordingMonitor: Any?
    private var changeObserver: NSObjectProtocol?

    init(hotkeys: Hotkeys) {
        self.hotkeys = hotkeys
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Горячие клавиши"
        window.minSize = NSSize(width: 520, height: 420)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self

        buildInterface()
        reloadRows()
        window.center()

        changeObserver = NotificationCenter.default.addObserver(forName: Hotkeys.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.reloadRows()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        stopRecording()
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    // MARK: - Вёрстка

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        searchField.placeholderString = "Поиск команды или сочетания"
        searchField.target = self
        searchField.action = #selector(searchChanged)

        let commandColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        commandColumn.title = "Команда"
        commandColumn.width = 330
        let keysColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("keys"))
        keysColumn.title = "Клавиши"
        keysColumn.width = 230
        tableView.addTableColumn(commandColumn)
        tableView.addTableColumn(keysColumn)
        tableView.style = .inset
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        commandLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        commandLabel.lineBreakMode = .byTruncatingTail

        combosStack.orientation = .horizontal
        combosStack.spacing = 6
        combosStack.alignment = .centerY

        addButton.target = self
        addButton.action = #selector(toggleRecording)
        defaultButton.target = self
        defaultButton.action = #selector(resetSelected)
        resetAllButton.target = self
        resetAllButton.action = #selector(resetAll)

        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let fileNote = NSTextField(wrappingLabelWithString: "Всё хранится в mTC-data/hotkeys.json — файл можно править вручную и передавать коллегам.")
        fileNote.textColor = .tertiaryLabelColor
        fileNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let bottom = NSStackView(views: [fileNote, resetAllButton])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        fileNote.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [searchField, scrollView, commandLabel, combosStack, hintLabel, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: scrollView)
        stack.setCustomSpacing(14, after: hintLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        for view in [searchField, scrollView, hintLabel, bottom] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        updateDetail()
    }

    // MARK: - Данные

    private var selectedInfo: CommandInfo? {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case .command(let info) = rows[row] else { return nil }
        return info
    }

    private func reloadRows() {
        let selected = selectedInfo?.command
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()

        var result: [Row] = []
        var currentCategory: String?
        for info in CommandCatalog.all {
            let keys = hotkeys.combos(for: info.command).map(\.displayString).joined(separator: " ").lowercased()
            guard query.isEmpty || info.title.lowercased().contains(query) || keys.contains(query) else { continue }
            if info.category != currentCategory {
                result.append(.header(info.category))
                currentCategory = info.category
            }
            result.append(.command(info))
        }
        rows = result
        tableView.reloadData()

        if let selected, let index = rows.firstIndex(where: { if case .command(let info) = $0 { return info.command == selected }; return false }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateDetail()
    }

    private func updateDetail() {
        combosStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let info = selectedInfo else {
            commandLabel.stringValue = "Выберите команду в списке"
            hintLabel.stringValue = "Клик по сочетанию удаляет его, «+ Добавить» — нажмите нужное сочетание."
            return
        }

        commandLabel.stringValue = info.title
        for (index, combo) in hotkeys.combos(for: info.command).enumerated() {
            let token = NSButton(title: "\(combo.displayString)  ✕", target: self, action: #selector(removeCombo(_:)))
            token.tag = index
            token.bezelStyle = .flexiblePush
            token.toolTip = "Удалить сочетание \(combo.displayString)"
            combosStack.addArrangedSubview(token)
        }
        combosStack.addArrangedSubview(addButton)
        combosStack.addArrangedSubview(defaultButton)

        let isDefault = hotkeys.combos(for: info.command) == info.defaults.compactMap(KeyCombo.init(string:))
        defaultButton.isEnabled = !isDefault
        if recordingMonitor == nil {
            addButton.title = info.command == .showHideWindow && !hotkeys.combos(for: info.command).isEmpty ? "Изменить" : "+ Добавить"
            let defaults = info.defaults.compactMap(KeyCombo.init(string:)).map(\.displayString).joined(separator: ", ")
            hintLabel.stringValue = info.command == .showHideWindow
                ? "Работает из любой программы. Нужен хотя бы один из ⌘, ⌃ или ⌥. По умолчанию: \(defaults)."
                : "По умолчанию: \(defaults.isEmpty ? "нет" : defaults)."
        }
    }

    // MARK: - Действия

    @objc private func searchChanged() {
        stopRecording()
        reloadRows()
    }

    @objc private func removeCombo(_ sender: NSButton) {
        guard let info = selectedInfo else { return }
        var combos = hotkeys.combos(for: info.command)
        guard combos.indices.contains(sender.tag) else { return }
        combos.remove(at: sender.tag)
        hotkeys.set(combos, for: info.command)
    }

    @objc private func resetSelected() {
        guard let info = selectedInfo else { return }
        stopRecording()
        hotkeys.resetToDefaults(info.command)
    }

    @objc private func resetAll() {
        guard let window else { return }
        stopRecording()
        let alert = NSAlert()
        alert.messageText = "Сбросить все горячие клавиши?"
        alert.informativeText = "Все сочетания вернутся к исходным. Свои изменения будут потеряны."
        alert.addButton(withTitle: "Сбросить").hasDestructiveAction = true
        alert.addCancelButton()
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.hotkeys.resetAll() }
        }
    }

    // MARK: - Запись сочетания

    @objc private func toggleRecording() {
        if recordingMonitor != nil {
            stopRecording()
            updateDetail()
            return
        }
        guard selectedInfo != nil else { return }
        addButton.title = "Нажмите сочетание…"
        hintLabel.stringValue = "Нажмите нужное сочетание клавиш. Esc — отмена."
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecorded(event)
            return nil
        }
    }

    private func stopRecording() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
    }

    private func handleRecorded(_ event: NSEvent) {
        guard let info = selectedInfo else {
            stopRecording()
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if Int(event.keyCode) == kVK_Escape, modifiers.isEmpty {
            stopRecording()
            updateDetail()
            return
        }
        guard let combo = KeyCombo(event: event) else { return }

        if let menuItem = CommandCatalog.reserved[combo] {
            hintLabel.stringValue = "\(combo.displayString) занято стандартным пунктом меню «\(menuItem)». Нажмите другое сочетание или Esc."
            return
        }
        let hasCommandModifier = !combo.modifiers.isDisjoint(with: [.command, .option, .control])
        if info.command == .showHideWindow {
            guard hasCommandModifier, combo.carbonKeyCode != nil else {
                hintLabel.stringValue = "Для глобальной клавиши нужен ⌘, ⌃ или ⌥ — иначе она мешала бы печатать в других программах."
                return
            }
        } else if !hasCommandModifier, case .code(let code) = combo.key, Self.typingKeys.contains(code) {
            hintLabel.stringValue = "Буквы и цифры без ⌘, ⌃ или ⌥ заняты быстрым переходом к файлу по имени. Добавьте модификатор."
            return
        }
        if hotkeys.combos(for: info.command).contains(combo) {
            hintLabel.stringValue = "\(combo.displayString) уже назначено этой команде."
            return
        }

        stopRecording()
        if let owner = hotkeys.command(for: combo), owner != info.command {
            confirmReassign(combo, from: owner, to: info)
        } else {
            assign(combo, to: info)
        }
    }

    private func confirmReassign(_ combo: KeyCombo, from owner: PanelCommand, to info: CommandInfo) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "\(combo.displayString) уже назначено команде «\(CommandCatalog.info(owner).title)»"
        alert.informativeText = "Переназначить на «\(info.title)»? У прежней команды это сочетание будет удалено."
        alert.addButton(withTitle: "Переназначить")
        alert.addCancelButton()
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                self.hotkeys.set(self.hotkeys.combos(for: owner).filter { $0 != combo }, for: owner)
                self.assign(combo, to: info)
            } else {
                self.updateDetail()
            }
        }
    }

    private func assign(_ combo: KeyCombo, to info: CommandInfo) {
        // У глобальной клавиши одно сочетание — новое заменяет старое.
        let combos = info.command == .showHideWindow ? [combo] : hotkeys.combos(for: info.command) + [combo]
        hotkeys.set(combos, for: info.command)
    }

    /// Буквы и цифры: без модификаторов ими пользуется быстрый поиск по имени в панели.
    private static let typingKeys: Set<Int> = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
        kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
        kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
        kVK_ANSI_Y, kVK_ANSI_Z, kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]
}

// MARK: - Таблица

extension HotkeysWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        let isHeader: Bool
        switch rows[row] {
        case .header(let title):
            text = title
            isHeader = true
        case .command(let info):
            isHeader = false
            if tableColumn?.identifier.rawValue == "keys" {
                let combos = hotkeys.combos(for: info.command)
                text = combos.isEmpty ? "—" : combos.map(\.displayString).joined(separator: ",  ")
            } else {
                text = info.title
            }
        }

        let identifier = NSUserInterfaceItemIdentifier(isHeader ? "header" : "cell")
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
            let field = NSTextField(labelWithString: "")
            field.identifier = identifier
            field.lineBreakMode = .byTruncatingTail
            return field
        }()
        field.stringValue = text
        field.font = isHeader
            ? .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            : .systemFont(ofSize: NSFont.systemFontSize)
        field.textColor = isHeader ? .secondaryLabelColor : (text == "—" ? .tertiaryLabelColor : .labelColor)
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        stopRecording()
        updateDetail()
    }
}
