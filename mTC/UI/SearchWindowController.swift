import AppKit
import Carbon.HIToolbox

/// Окно поиска файлов (⌥F7 / ⌘F): где искать, маска имени, текст внутри, дата, результаты по мере нахождения.
/// Поиск запускается только кнопкой «Найти» (или Enter в поле ввода).
/// Двойной щелчок или Enter по результату — перейти к файлу в активной панели. Esc — остановить поиск,
/// а если он не идёт — закрыть окно. Окно не модальное; при повторном открытии результаты остаются.
final class SearchWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSWindowDelegate {
    /// Перейти к найденному в панели.
    var onReveal: ((SearchHit) -> Void)?
    /// Условия поиска, с которыми запустили поиск (чтобы запомнить).
    var onQueryUsed: ((SearchQuery) -> Void)?

    private let rootField = NSTextField(string: "")
    private let nameField = NSTextField(string: "")
    private let textField = NSTextField(string: "")
    private let caseCheckbox = NSButton(checkboxWithTitle: "Учитывать регистр", target: nil, action: nil)
    private let hiddenCheckbox = NSButton(checkboxWithTitle: "Скрытые файлы и папки", target: nil, action: nil)
    private let dateFieldPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let datePeriodPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let dateFromPicker = NSDatePicker()
    private let dateToPicker = NSDatePicker()
    private let dateToLabel = NSTextField(labelWithString: "по")
    private let searchButton = NSButton(title: "Найти", target: nil, action: nil)
    private let revealButton = NSButton(title: "Перейти к файлу", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let tableView = SearchResultsTableView()

    private var hits: [SearchHit] = []
    private var searchRoot: URL?
    private var operation: FileSearchOperation?
    private var scannedDirectories = 0
    /// Какая дата показана в колонке результатов — та, по которой искали.
    private var shownDate = SearchDateField.modified

    private enum Column: String, CaseIterable {
        case name, folder, size, date

        var title: String {
            switch self {
            case .name: return "Имя"
            case .folder: return "Папка"
            case .size: return "Размер"
            case .date: return SearchDateField.modified.title
            }
        }

        var width: CGFloat {
            switch self {
            case .name: return 230
            case .folder: return 250
            case .size: return 90
            case .date: return 140
            }
        }
    }

    /// Размер в байтах с разрядами — как в панелях.
    private static let sizeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()

    init(query: SearchQuery) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Поиск файлов"
        window.minSize = NSSize(width: 560, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        nameField.stringValue = query.name
        textField.stringValue = query.text
        caseCheckbox.state = query.caseSensitive ? .on : .off
        hiddenCheckbox.state = query.includeHidden ? .on : .off
        dateFieldPopup.addItems(withTitles: SearchDateField.allCases.map(\.title))
        dateFieldPopup.selectItem(at: SearchDateField.allCases.firstIndex(of: query.dateField) ?? 0)
        datePeriodPopup.addItems(withTitles: SearchDatePeriod.allCases.map(\.title))
        datePeriodPopup.selectItem(at: SearchDatePeriod.allCases.firstIndex(of: query.datePeriod) ?? 0)
        dateFromPicker.dateValue = query.dateFrom
        dateToPicker.dateValue = query.dateTo
        buildLayout()
        updateDateControls()
        updateButtons()
        statusLabel.stringValue = "Маска имени: «*.pdf; отчёт» — без * и ? ищется часть имени. Пусто — любое имя."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    // MARK: - Показ

    /// Показывает окно над главным. Если поиск не идёт, «Искать в» — папка активной панели.
    func show(root: URL, over parent: NSWindow?) {
        guard let window else { return }
        if operation == nil {
            rootField.stringValue = root.path
        }
        if !window.isVisible, let parent {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        }
        showWindow(nil)
        window.makeFirstResponder(hits.isEmpty ? nameField : tableView)
        if hits.isEmpty { nameField.currentEditor()?.selectAll(nil) }
    }

    // MARK: - Раскладка

    private func buildLayout() {
        guard let content = window?.contentView else { return }

        for field in [rootField, nameField, textField] {
            field.target = self
            field.action = #selector(fieldSubmitted)
            // Иначе поле шлёт действие и при уходе фокуса — поиск запускался сам при открытии окна.
            field.cell?.sendsActionOnEndEditing = false
            field.lineBreakMode = .byTruncatingMiddle
            field.cell?.isScrollable = true
        }
        nameField.placeholderString = "любое имя"
        textField.placeholderString = "не проверять содержимое"

        let browseButton = NSButton(title: "Выбрать…", target: self, action: #selector(browse))
        let maskHelpButton = NSButton(title: "", target: self, action: #selector(showMaskHelp(_:)))
        maskHelpButton.bezelStyle = .helpButton
        maskHelpButton.toolTip = "Как писать маску имени"
        searchButton.target = self
        searchButton.action = #selector(toggleSearch)
        searchButton.bezelColor = .controlAccentColor
        revealButton.target = self
        revealButton.action = #selector(revealSelected)

        let options = NSStackView(views: [caseCheckbox, hiddenCheckbox])
        options.spacing = 16

        for picker in [dateFromPicker, dateToPicker] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .yearMonthDay
        }
        datePeriodPopup.target = self
        datePeriodPopup.action = #selector(datePeriodChanged)
        let dateRow = NSStackView(views: [dateFieldPopup, datePeriodPopup, dateFromPicker, dateToLabel, dateToPicker])
        dateRow.spacing = 8

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Искать в:"), rootField, browseButton],
            [NSTextField(labelWithString: "Имя файла:"), nameField, maskHelpButton],
            [NSTextField(labelWithString: "Текст в файле:"), textField, NSGridCell.emptyContentView],
            [NSTextField(labelWithString: "Дата:"), dateRow, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, options, NSGridCell.emptyContentView],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 2).xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        grid.cell(for: maskHelpButton)?.yPlacement = .center
        grid.rowSpacing = 8
        grid.columnSpacing = 8

        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            if column == .date { tableColumn.minWidth = 130 }
            if column == .size { tableColumn.headerCell.alignment = .right }
            tableView.addTableColumn(tableColumn)
        }
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(revealClicked)
        tableView.onReturn = { [weak self] in self?.revealSelected() }
        tableView.onEscape = { [weak self] in self?.cancelOperation(nil) }
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [grid, searchButton, scroll, statusLabel, revealButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            rootField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),

            searchButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
            searchButton.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            searchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

            scroll.topAnchor.constraint(equalTo: searchButton.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            revealButton.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            revealButton.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            revealButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

            statusLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: revealButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: revealButton.leadingAnchor, constant: -12),
        ])
    }

    // MARK: - Поиск

    private var currentQuery: SearchQuery {
        SearchQuery(
            name: nameField.stringValue.trimmingCharacters(in: .whitespaces),
            text: textField.stringValue,
            caseSensitive: caseCheckbox.state == .on,
            includeHidden: hiddenCheckbox.state == .on,
            dateField: SearchDateField.allCases[max(dateFieldPopup.indexOfSelectedItem, 0)],
            datePeriod: SearchDatePeriod.allCases[max(datePeriodPopup.indexOfSelectedItem, 0)],
            dateFrom: dateFromPicker.dateValue,
            dateTo: dateToPicker.dateValue
        )
    }

    @objc private func datePeriodChanged() {
        updateDateControls()
    }

    /// «с … по …» — даты видны только для интервала; тип даты не нужен, если дата не важна.
    private func updateDateControls() {
        let period = SearchDatePeriod.allCases[max(datePeriodPopup.indexOfSelectedItem, 0)]
        dateFieldPopup.isEnabled = period != .any
        for view in [dateFromPicker, dateToLabel, dateToPicker] as [NSView] {
            view.isHidden = period != .interval
        }
    }

    @objc private func fieldSubmitted() {
        if operation == nil { startSearch() }
    }

    @objc private func toggleSearch() {
        if let operation {
            operation.cancel()
        } else {
            startSearch()
        }
    }

    private func startSearch() {
        let path = (rootField.stringValue.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            statusLabel.stringValue = "Папка «\(rootField.stringValue)» не найдена."
            NSSound.beep()
            window?.makeFirstResponder(rootField)
            return
        }
        let root = URL(fileURLWithPath: path)
        let query = currentQuery
        onQueryUsed?(query)

        hits.removeAll()
        // В колонке — дата, по которой ищем (без фильтра — дата изменения).
        shownDate = query.datePeriod == .any ? .modified : query.dateField
        tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(Column.date.rawValue))?.title = shownDate.title
        tableView.reloadData()
        searchRoot = root
        scannedDirectories = 0

        let operation = FileSearchOperation(root: root, query: query)
        operation.onHits = { [weak self] newHits in
            guard let self else { return }
            let start = self.hits.count
            self.hits.append(contentsOf: newHits)
            self.tableView.insertRows(at: IndexSet(start..<self.hits.count), withAnimation: [])
            if start == 0 { self.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        }
        operation.onProgress = { [weak self] progress in
            guard let self else { return }
            self.scannedDirectories = progress.scannedDirectories
            self.statusLabel.stringValue = "Найдено: \(self.hits.count) · \(progress.currentDirectory)"
        }
        operation.onFinish = { [weak self] cancelled in
            guard let self else { return }
            self.operation = nil
            let found = self.hits.isEmpty ? "Ничего не найдено" : "Найдено: \(self.hits.count)"
            self.statusLabel.stringValue = "\(found) · просмотрено папок: \(self.scannedDirectories)\(cancelled ? " · остановлено" : "")"
            self.updateButtons()
            if !self.hits.isEmpty, self.window?.firstResponder !== self.tableView {
                self.window?.makeFirstResponder(self.tableView)
            }
        }
        self.operation = operation
        updateButtons()
        statusLabel.stringValue = "Поиск…"
        operation.start()
    }

    private func updateButtons() {
        let running = operation != nil
        searchButton.title = running ? "Стоп" : "Найти"
        revealButton.isEnabled = selectedHit != nil
    }

    /// «?» у поля имени: как писать маску.
    @objc private func showMaskHelp(_ sender: NSButton) {
        let rows: [(String, String)] = [
            ("*.pdf", "все PDF"),
            ("отчёт*", "имя начинается с «отчёт»"),
            ("IMG_????.jpg", "? — ровно один символ: IMG_0042.jpg"),
            ("отчёт", "без * и ? — имя содержит «отчёт»"),
            ("*.pdf; *.docx; договор", "несколько масок через «;» — подходит любая"),
            ("(пусто)", "любое имя — ищем по тексту или дате"),
        ]
        let grid = NSGridView(views: rows.map { mask, meaning in
            let maskLabel = NSTextField(labelWithString: mask)
            maskLabel.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            return [maskLabel, NSTextField(labelWithString: meaning)]
        })
        grid.rowSpacing = 6
        grid.columnSpacing = 14
        let note = NSTextField(wrappingLabelWithString: "Регистр не важен. Пробел — часть имени. Проверяется только имя, без пути.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let stack = NSStackView(views: [grid, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        note.preferredMaxLayoutWidth = grid.fittingSize.width
        stack.layoutSubtreeIfNeeded()

        let controller = NSViewController()
        controller.view = stack
        let popover = NSPopover()
        popover.contentViewController = controller
        // Запас справа: поповер добавляет свои поля, и длинная строка иначе упирается в край.
        popover.contentSize = NSSize(width: stack.fittingSize.width + 16, height: stack.fittingSize.height)
        popover.behavior = .transient
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
    }

    @objc private func browse() {
        guard let window else { return }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.prompt = "Выбрать"
        picker.directoryURL = URL(fileURLWithPath: (rootField.stringValue as NSString).expandingTildeInPath)
        picker.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = picker.url { self?.rootField.stringValue = url.path }
        }
    }

    /// Esc: остановить поиск, а если он не идёт — закрыть окно.
    override func cancelOperation(_ sender: Any?) {
        if let operation {
            operation.cancel()
        } else {
            window?.performClose(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        operation?.cancel()
    }

    // MARK: - Результаты

    private var selectedHit: SearchHit? {
        let row = tableView.selectedRow
        return hits.indices.contains(row) ? hits[row] : nil
    }

    @objc private func revealClicked() {
        let row = tableView.clickedRow
        guard hits.indices.contains(row) else { return }
        onReveal?(hits[row])
    }

    @objc private func revealSelected() {
        if let hit = selectedHit { onReveal?(hit) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        hits.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier, let column = Column(rawValue: identifier.rawValue) else { return nil }
        let hit = hits[row]
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier, withImage: column == .name)

        let text: String
        switch column {
        case .name:
            text = hit.url.lastPathComponent
            cell.imageView?.image = IconProvider.icon(for: fileItem(for: hit))
        case .folder:
            text = relativeFolder(of: hit.url)
        case .size:
            text = hit.size.flatMap { Self.sizeFormatter.string(from: NSNumber(value: $0)) } ?? (hit.isDirectory ? "<DIR>" : "")
        case .date:
            text = (shownDate == .created ? hit.created : hit.modified).map(Self.dateFormatter.string(from:)) ?? ""
        }
        cell.textField?.stringValue = text
        cell.textField?.alignment = column == .size ? .right : .left
        cell.textField?.textColor = column == .name ? FileColors.shared.color(for: fileItem(for: hit)) ?? .labelColor : .labelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier, withImage: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        var constraints = [
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
        ]
        if withImage {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            constraints += [
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            ]
        } else {
            constraints.append(label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }

    private func fileItem(for hit: SearchHit) -> FileItem {
        let isPackage = !hit.isDirectory && (try? hit.url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
        return FileItem(
            url: hit.url,
            kind: hit.isDirectory ? .directory : (isPackage ? .package : .file),
            name: hit.url.lastPathComponent,
            size: hit.size,
            modified: hit.modified,
            isHidden: hit.isHidden,
            isSymlink: false
        )
    }

    /// Папка находки относительно «Искать в» (сама она — «.»). Пути сравниваем после разворота ссылок:
    /// `/tmp` и `/private/tmp` — одна папка.
    private func relativeFolder(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard let root = searchRoot?.resolvingSymlinksInPath().path else { return folder }
        if folder == root { return "." }
        let prefix = root == "/" ? "/" : root + "/"
        return folder.hasPrefix(prefix) ? String(folder.dropFirst(prefix.count)) : folder
    }

    // MARK: - Контекстное меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard hits.indices.contains(row) else { return }
        let hit = hits[row]
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        menu.addItem(ActionMenuItem("Перейти к файлу") { [weak self] in self?.onReveal?(hit) })
        menu.addItem(ActionMenuItem("Открыть") { NSWorkspace.shared.open(hit.url) })
        menu.addItem(ActionMenuItem("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([hit.url]) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Скопировать путь") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hit.url.path, forType: .string)
        })
    }
}

/// Таблица результатов: Enter — перейти к файлу, Esc — остановить или закрыть.
final class SearchResultsTableView: NSTableView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: onReturn?()
        case kVK_Escape: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}
