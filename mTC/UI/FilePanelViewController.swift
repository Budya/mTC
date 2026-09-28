import AppKit
import Quartz

protocol FilePanelDelegate: AnyObject {
    func filePanelDidBecomeActive(_ panel: FilePanelViewController)
    func filePanelDidChangeDirectory(_ panel: FilePanelViewController)
    func filePanelRequestsFocusSwitch(_ panel: FilePanelViewController)
    /// Панель просит спросить маску (`marking == false` — снять отметку по маске).
    func filePanel(_ panel: FilePanelViewController, requestsMaskForMarking marking: Bool)
    /// ⌃Tab / ⌃⇧Tab: переключиться на соседнюю вкладку.
    func filePanel(_ panel: FilePanelViewController, requestsTabOffset offset: Int)
    /// F7: спросить имя новой папки.
    func filePanelRequestsNewDirectory(_ panel: FilePanelViewController)
    /// Скопировать `targets` в другую панель (F5 / контекстное меню).
    func filePanel(_ panel: FilePanelViewController, requestsCopyOf targets: [FileItem])
    /// Переместить `targets` в другую панель (F6 / контекстное меню).
    func filePanel(_ panel: FilePanelViewController, requestsMoveOf targets: [FileItem])
    /// F4: открыть `targets` в редакторе.
    func filePanel(_ panel: FilePanelViewController, requestsEditOf targets: [FileItem])
    /// ⇧F4: спросить имя нового файла.
    func filePanelRequestsNewFile(_ panel: FilePanelViewController)
    /// ⌘↵ / средний клик по папке: открыть её в новой вкладке.
    func filePanel(_ panel: FilePanelViewController, requestsNewTabWith directory: URL)
    /// Команды окна (обновить, вкладки, скрытые файлы) — панель передаёт их окну.
    func filePanel(_ panel: FilePanelViewController, performWindowCommand command: PanelCommand)
    /// ⌘\\: папка другой панели (перейти в неё).
    func filePanelOppositeDirectory(_ panel: FilePanelViewController) -> URL?
    /// Файлы перетащили в панель (из другой панели или из Finder).
    func filePanel(_ panel: FilePanelViewController, requestsDropOf urls: [URL], into directory: URL, move: Bool)
    /// Упаковать `targets` в архив (⌥F5 / контекстное меню).
    func filePanel(_ panel: FilePanelViewController, requestsPackOf targets: [FileItem])
    /// Распаковать архивы из `targets` в текущую папку (⌥F9 / контекстное меню).
    func filePanel(_ panel: FilePanelViewController, requestsExtractOf targets: [FileItem])
    /// Открыли архив (Enter / двойной щелчок): спросить, распаковать или открыть программой.
    func filePanel(_ panel: FilePanelViewController, requestsOpenOfArchive archive: FileItem)
    /// Удалить `targets` (F8 / ⇧F8 / контекстное меню).
    func filePanel(_ panel: FilePanelViewController, requestsDeletionOf targets: [FileItem], permanently: Bool)
}

/// Состояние вкладки: папка, курсор, выделение и сортировка.
struct PanelTab {
    var directory: URL
    var cursorName: String?
    var marked: Set<String> = []
    var sortKey: SortKey = .name
    var sortAscending = true
    var back: [HistoryEntry] = []
    var forward: [HistoryEntry] = []

    var title: String {
        directory.path == "/" ? "/" : directory.lastPathComponent
    }
}

/// Запись истории переходов: папка и файл, на котором стоял курсор.
struct HistoryEntry {
    var directory: URL
    var cursorName: String?
}

/// Одна файловая панель: путь сверху, список файлов, строка состояния снизу.
///
/// Курсор — это выделенная строка таблицы. Отмеченные файлы (Space, Insert, `+`, `-`, `*`)
/// хранятся отдельно, по имени, и подсвечиваются красным — как в Total Commander.
final class FilePanelViewController: NSViewController {
    private enum Column: String {
        case name, ext, size, modified
    }

    let side: PanelSide
    weak var delegate: FilePanelDelegate?
    private(set) var directory: URL

    var showHiddenFiles: Bool {
        didSet { if oldValue != showHiddenFiles { reload() } }
    }

    var isActive = false {
        didSet { updateActiveAppearance() }
    }

    private var items: [FileItem] = []
    private var sortKey: SortKey = .name
    private var sortAscending = true

    /// Имена отмеченных файлов текущей папки.
    private var marked: Set<String> = []
    /// Посчитанные размеры папок (по Space) текущей папки.
    private var directorySizes: [String: Int64] = [:]
    private var sizingInProgress: Set<String> = []
    private var sizingCancellation = CancellationFlag()

    /// Выделение диапазоном: якорь — последняя строка, где стоял курсор или которую отметили,
    /// `rangeBase` — отметки на момент начала диапазона.
    private var rangeAnchor = 0
    private var rangeBase: Set<String>?
    private var isExtendingRange = false

    /// Автообновление: следим за текущей папкой.
    private var watcher: DirectoryWatcher?
    private var watchedDirectory: URL?

    /// Переименование прямо в списке (⇧F6 / F2).
    private var renamingItem: FileItem?
    private var renameCancelled = false
    /// Пока идёт переименование, обновление откладываем — иначе таблица пересоздаст ячейку с полем ввода.
    private var reloadPendingAfterRename = false

    /// Quick Look (F3): что сейчас показываем и управляет ли просмотром эта панель.
    private var previewItems: [URL] = []
    private var isPreviewController = false

    /// Куда и как бросят перетаскиваемое (вычисляется при наведении).
    private var dropTarget: URL?
    private var dropIsMove = false

    /// Выбор диска: последняя открытая папка на каждом томе (как в Total Commander).
    private let driveBar = DriveBar()
    private var lastDirectoryByVolume: [URL: URL] = [:]
    /// Том текущей папки (запоминаем, чтобы понять, что его отключили).
    private var currentVolume: URL?
    private var volumeObservers: [NSObjectProtocol] = []

    /// История переходов (⌘[ / ⌘]) — у каждой вкладки своя, хранится в `PanelTab`.
    private var backStack: [HistoryEntry] = []
    private var forwardStack: [HistoryEntry] = []
    private static let historyLimit = 100

    private let headerBox = NSBox()
    private let pathLabel = NSTextField(labelWithString: "")
    /// Поле ввода пути (⌘L или клик по строке пути), поверх `pathLabel`.
    private let pathField = NSTextField(string: "")
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let scrollView = NSScrollView()
    private let tableView = PanelTableView()
    private let statusLabel = NSTextField(labelWithString: "")

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

    init(side: PanelSide, directory: URL, showHiddenFiles: Bool) {
        self.side = side
        self.directory = directory
        self.showHiddenFiles = showHiddenFiles
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    deinit {
        sizingCancellation.cancel()
        volumeObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    // MARK: - Вёрстка

    override func loadView() {
        let root = NSView()

        headerBox.boxType = .custom
        headerBox.borderWidth = 0
        headerBox.cornerRadius = 0
        headerBox.titlePosition = .noTitle
        headerBox.contentViewMargins = .zero

        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        pathLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(pathLabelClicked)))
        pathLabel.toolTip = "Нажмите, чтобы ввести путь (⌘L)"

        pathField.font = pathLabel.font
        pathField.isBordered = false
        pathField.focusRingType = .none
        pathField.drawsBackground = true
        pathField.backgroundColor = .textBackgroundColor
        pathField.textColor = .textColor
        pathField.lineBreakMode = .byTruncatingHead
        pathField.cell?.isScrollable = true
        pathField.delegate = self
        pathField.isHidden = true

        for (button, symbol, tip, action) in [
            (backButton, "chevron.left", "Назад (⌘[)", #selector(backClicked)),
            (forwardButton, "chevron.right", "Вперёд (⌘])", #selector(forwardClicked)),
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            button.isBordered = false
            button.refusesFirstResponder = true
            button.toolTip = tip
            button.target = self
            button.action = action
        }

        for subview in [backButton, forwardButton, pathLabel, pathField] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            headerBox.contentView?.addSubview(subview)
        }

        configureTable()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        driveBar.onSelect = { [weak self] choice in self?.selectDrive(choice) }
        observeVolumes()

        for subview in [driveBar, headerBox, scrollView, statusLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }

        if let headerContent = headerBox.contentView {
            NSLayoutConstraint.activate([
                backButton.leadingAnchor.constraint(equalTo: headerContent.leadingAnchor, constant: 4),
                backButton.centerYAnchor.constraint(equalTo: headerContent.centerYAnchor),
                backButton.widthAnchor.constraint(equalToConstant: 16),
                forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
                forwardButton.centerYAnchor.constraint(equalTo: headerContent.centerYAnchor),
                forwardButton.widthAnchor.constraint(equalToConstant: 16),

                pathLabel.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 6),
                pathLabel.trailingAnchor.constraint(equalTo: headerContent.trailingAnchor, constant: -6),
                pathLabel.centerYAnchor.constraint(equalTo: headerContent.centerYAnchor),

                pathField.leadingAnchor.constraint(equalTo: pathLabel.leadingAnchor, constant: -2),
                pathField.trailingAnchor.constraint(equalTo: headerContent.trailingAnchor, constant: -3),
                pathField.centerYAnchor.constraint(equalTo: headerContent.centerYAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            driveBar.topAnchor.constraint(equalTo: root.topAnchor),
            driveBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            driveBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            headerBox.topAnchor.constraint(equalTo: driveBar.bottomAnchor),
            headerBox.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerBox.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerBox.heightAnchor.constraint(equalToConstant: 22),

            scrollView.topAnchor.constraint(equalTo: headerBox.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            statusLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 3),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),

            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
        ])

        view = root
        updateActiveAppearance()
    }

    private func configureTable() {
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.rowHeight = 20
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        addColumn(.name, title: "Имя", width: 240, minWidth: 100)
        addColumn(.ext, title: "Тип", width: 60, minWidth: 40)
        addColumn(.size, title: "Размер", width: 100, minWidth: 60)
        addColumn(.modified, title: "Дата", width: 120, minWidth: 80)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openClickedRow)
        tableView.sortDescriptors = [NSSortDescriptor(key: Column.name.rawValue, ascending: true)]

        tableView.onCommand = { [weak self] command in self?.perform(command) }
        tableView.onToggleMarkAtRow = { [weak self] row in self?.toggleMark(at: row, moveBy: 0) }
        tableView.onExtendRangeToRow = { [weak self] row in self?.extendRange(to: row) }
        tableView.onPlainClick = { [weak self] in self?.setMarks([]) }
        tableView.onContextMenu = { [weak self] row in self?.contextMenu(forRow: row) }
        tableView.dragURLsForRow = { [weak self] row in self?.dragURLs(forRow: row) }
        tableView.onMiddleClick = { [weak self] row in
            guard let self, let item = self.item(at: row), item.isContainer else { return }
            self.delegate?.filePanel(self, requestsNewTabWith: item.url)
        }

        // Перетаскивание: внутри mTC — копия (с ⌘ — перемещение); наружу (Finder и др.) — только копия.
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.draggingDestinationFeedbackStyle = .regular
        tableView.onFocus = { [weak self] in
            guard let self else { return }
            self.delegate?.filePanelDidBecomeActive(self)
        }
    }

    private func addColumn(_ column: Column, title: String, width: CGFloat, minWidth: CGFloat) {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
        tableColumn.title = title
        tableColumn.width = width
        tableColumn.minWidth = minWidth
        tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
        if column == .size {
            tableColumn.headerCell.alignment = .right
        }
        tableView.addTableColumn(tableColumn)
    }

    private func updateActiveAppearance() {
        headerBox.fillColor = isActive ? .controlAccentColor : .quaternaryLabelColor
        pathLabel.textColor = isActive ? .alternateSelectedControlTextColor : .labelColor
        for button in [backButton, forwardButton] {
            button.contentTintColor = isActive ? .alternateSelectedControlTextColor : .secondaryLabelColor
        }
    }

    // MARK: - Команды

    func perform(_ command: PanelCommand) {
        switch command {
        case .open: openCursorRow()
        case .goUp: goUp()
        case .switchPanel: delegate?.filePanelRequestsFocusSwitch(self)
        case .toggleMark: toggleMark(at: tableView.selectedRow, moveBy: 1)
        case .invertMovingUp: toggleMark(at: tableView.selectedRow, moveBy: -1, measureDirectories: false)
        case .invertMovingDown: toggleMark(at: tableView.selectedRow, moveBy: 1, measureDirectories: false)
        case .markByMask: delegate?.filePanel(self, requestsMaskForMarking: true)
        case .unmarkByMask: delegate?.filePanel(self, requestsMaskForMarking: false)
        case .invertMarks: invertMarks()
        case .markAll: setMarks(allNames)
        case .unmarkAll: setMarks([])
        case .toggleMarkAll: setMarks(!allNames.isEmpty && marked == allNames ? [] : allNames)
        case .nextTab: delegate?.filePanel(self, requestsTabOffset: 1)
        case .previousTab: delegate?.filePanel(self, requestsTabOffset: -1)
        case .makeDirectory: delegate?.filePanelRequestsNewDirectory(self)
        case .goBack: goBack()
        case .goForward: goForward()
        case .goHome: navigate(to: FileManager.default.homeDirectoryForCurrentUser)
        case .goToVolumeRoot: navigate(to: currentVolume ?? URL(fileURLWithPath: "/"))
        case .goToOppositeDirectory:
            if let other = delegate?.filePanelOppositeDirectory(self) { navigate(to: other) }
        case .editPath: beginPathEditing()
        case .openInNewTab:
            if let item = item(at: tableView.selectedRow), item.isContainer {
                delegate?.filePanel(self, requestsNewTabWith: item.url)
            }
        case .refresh, .toggleHiddenFiles, .newTab, .closeTab, .search, .compareDirectories, .showHideWindow:
            delegate?.filePanel(self, performWindowCommand: command)
        case .quickLook: togglePreview()
        case .edit: delegate?.filePanel(self, requestsEditOf: operationTargets())
        case .newFile: delegate?.filePanelRequestsNewFile(self)
        case .closePreview: closePreview()
        case .copyToOtherPanel: delegate?.filePanel(self, requestsCopyOf: operationTargets())
        case .moveToOtherPanel: delegate?.filePanel(self, requestsMoveOf: operationTargets())
        case .rename: beginRename()
        case .extractArchive: delegate?.filePanel(self, requestsExtractOf: operationTargets())
        case .createArchive: delegate?.filePanel(self, requestsPackOf: operationTargets())
        case .moveToTrash: delegate?.filePanel(self, requestsDeletionOf: operationTargets(), permanently: false)
        case .deletePermanently: delegate?.filePanel(self, requestsDeletionOf: operationTargets(), permanently: true)
        }
    }

    func focus() {
        view.window?.makeFirstResponder(tableView)
    }

    // MARK: - Вкладки

    func snapshot() -> PanelTab {
        PanelTab(
            directory: directory,
            cursorName: item(at: tableView.selectedRow)?.name,
            marked: marked,
            sortKey: sortKey,
            sortAscending: sortAscending,
            back: backStack,
            forward: forwardStack
        )
    }

    /// Показывает сохранённую вкладку. Если её папки больше нет — ближайшую существующую или домашнюю.
    func restore(_ tab: PanelTab) {
        _ = view
        sortKey = tab.sortKey
        sortAscending = tab.sortAscending
        tableView.sortDescriptors = [NSSortDescriptor(key: tab.sortKey.rawValue, ascending: tab.sortAscending)]
        marked = []

        var target = tab.directory
        while !FileManager.default.fileExists(atPath: target.path), target.path != "/" {
            target = target.deletingLastPathComponent()
        }
        if !navigate(to: target, selecting: tab.cursorName, reportErrors: false, recordHistory: false) {
            navigate(to: FileManager.default.homeDirectoryForCurrentUser, reportErrors: false, recordHistory: false)
        }
        backStack = tab.back
        forwardStack = tab.forward
        updateHistoryButtons()

        marked = target == tab.directory ? tab.marked.intersection(allNames) : []
        rangeBase = nil
        reloadVisibleRows()
        updateLabels()
    }

    // MARK: - Навигация

    /// Открывает папку. Возвращает `false`, если прочитать её не удалось.
    /// При повторном открытии той же папки (обновлении) отметки и посчитанные размеры сохраняются.
    /// `fallbackRow` — куда поставить курсор, если файла `name` больше нет.
    @discardableResult
    func navigate(to url: URL, selecting name: String? = nil, fallbackRow: Int = 0, reportErrors: Bool = true, recordHistory: Bool = true) -> Bool {
        _ = view
        let target = url.standardizedFileURL
        let listed: [FileItem]
        do {
            listed = try DirectoryLister.list(target, showHidden: showHiddenFiles)
        } catch {
            if reportErrors { showError(error, opening: target) }
            return false
        }

        if target == directory {
            let names = Set(listed.map(\.name))
            marked.formIntersection(names)
            directorySizes = directorySizes.filter { names.contains($0.key) }
        } else {
            if recordHistory, isViewLoaded, !items.isEmpty {
                backStack.append(HistoryEntry(directory: directory, cursorName: item(at: tableView.selectedRow)?.name))
                if backStack.count > Self.historyLimit { backStack.removeFirst() }
                forwardStack.removeAll()
            }
            marked.removeAll()
            directorySizes.removeAll()
            sizingInProgress.removeAll()
            sizingCancellation.cancel()
            sizingCancellation = CancellationFlag()
        }

        directory = target
        items = arrange(listed)
        tableView.reloadData()
        watch(target)

        let row = name.flatMap { name in items.firstIndex { $0.name == name } } ?? fallbackRow
        moveCursor(to: row)
        resetRange(anchor: tableView.selectedRow)
        updateLabels()
        currentVolume = Volumes.volumeURL(containing: target)
        if let currentVolume {
            lastDirectoryByVolume[currentVolume] = target
        }
        refreshDriveBar()
        updateHistoryButtons()
        delegate?.filePanelDidChangeDirectory(self)
        return true
    }

    /// Перечитывает текущую папку, сохраняя курсор и отметки.
    /// Если папку удалили — поднимается к ближайшей существующей и ставит курсор на ветку, из которой пришли.
    func reload(reportErrors: Bool = true) {
        guard renamingItem == nil else {
            reloadPendingAfterRename = true
            return
        }
        var target = directory
        var cameFrom: String?
        while !FileManager.default.fileExists(atPath: target.path), target.path != "/" {
            cameFrom = target.lastPathComponent
            target = target.deletingLastPathComponent()
        }

        if target == directory {
            navigate(
                to: target,
                selecting: item(at: tableView.selectedRow)?.name,
                fallbackRow: tableView.selectedRow,
                reportErrors: reportErrors
            )
        } else if currentVolume != nil, Volumes.volumeURL(containing: target) != currentVolume {
            // Папка пропала вместе с диском (его отключили) — уходим в домашнюю папку.
            navigate(to: FileManager.default.homeDirectoryForCurrentUser, reportErrors: false, recordHistory: false)
        } else {
            navigate(to: target, selecting: cameFrom, reportErrors: false, recordHistory: false)
        }
    }

    private func watch(_ url: URL) {
        guard watchedDirectory != url else { return }
        watchedDirectory = url
        watcher = DirectoryWatcher(url: url) { [weak self] in
            self?.reload(reportErrors: false)
        }
    }

    func goUp() {
        guard directory.path != "/" else { return }
        navigate(to: directory.deletingLastPathComponent(), selecting: directory.lastPathComponent)
    }

    @objc private func openClickedRow() {
        if let item = item(at: tableView.clickedRow) { open(item) }
    }

    private func openCursorRow() {
        if let item = item(at: tableView.selectedRow) { open(item) }
    }

    private func open(_ item: FileItem) {
        switch item.kind {
        case .parent:
            goUp()
        case .directory:
            navigate(to: item.url)
        case .file where ArchiveFormats.asksOnOpen(item.url):
            delegate?.filePanel(self, requestsOpenOfArchive: item)
        case .package, .file:
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: - Диски

    private func refreshDriveBar() {
        driveBar.update(volumes: Volumes.mounted(), directory: directory, capacity: Volumes.capacity(of: directory))
    }

    private func selectDrive(_ choice: DriveBar.Choice) {
        switch choice {
        case .home:
            navigate(to: FileManager.default.homeDirectoryForCurrentUser)
        case .root:
            navigate(to: URL(fileURLWithPath: "/"))
        case .volume(let volume):
            // Как в TC: выбор текущего диска открывает его корень, другого — последнюю папку на нём.
            if Volumes.volumeURL(containing: directory) == volume.url {
                navigate(to: volume.url)
            } else if let last = lastDirectoryByVolume[volume.url],
                      FileManager.default.fileExists(atPath: last.path),
                      navigate(to: last, reportErrors: false) {
                break
            } else {
                navigate(to: volume.url)
            }
        }
        refreshDriveBar()
        focus()
    }

    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didRenameVolumeNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshDriveBar()
            })
        }
        volumeObservers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] notification in
            self?.volumeDidUnmount(notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)
        })
    }

    /// Диск, открытый в панели, отключили — уходим в домашнюю папку.
    private func volumeDidUnmount(_ volumeURL: URL?) {
        if let volumeURL {
            let volumePath = volumeURL.standardizedFileURL.path
            lastDirectoryByVolume = lastDirectoryByVolume.filter { $0.key.standardizedFileURL.path != volumePath }
            let current = directory.path
            let isOnVolume = current == volumePath || current.hasPrefix(volumePath.hasSuffix("/") ? volumePath : volumePath + "/")
            if volumePath != "/", isOnVolume || currentVolume?.standardizedFileURL.path == volumePath {
                navigate(to: FileManager.default.homeDirectoryForCurrentUser, reportErrors: false)
            }
        }
        refreshDriveBar()
    }

    // MARK: - Файловые операции

    // MARK: Переименование

    /// Делает имя под курсором редактируемым; выделена часть без расширения, как в Finder.
    func beginRename() {
        let row = tableView.selectedRow
        guard renamingItem == nil, let item = item(at: row), item.kind != .parent else { return }
        tableView.scrollRowToVisible(row)
        guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? PanelCellView,
              let field = cell.textField else { return }

        renamingItem = item
        renameCancelled = false
        field.stringValue = item.name
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.textColor = .textColor
        field.delegate = self
        view.window?.makeFirstResponder(field)

        let name = item.name as NSString
        let ext = item.kind == .directory ? "" : item.ext
        let stemLength = ext.isEmpty ? name.length : name.length - (ext as NSString).length - 1
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: max(stemLength, 0))
    }

    private func finishRename(_ field: NSTextField) {
        guard let item = renamingItem else { return }
        renamingItem = nil
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.delegate = nil

        let newName = field.stringValue.trimmingCharacters(in: .newlines)
        if renameCancelled || newName.isEmpty || newName == item.name {
            finishRenameCleanup(selecting: item.name)
            return
        }

        do {
            try FileOperations.rename(item.url, to: newName)
            if marked.remove(item.name) != nil { marked.insert(newName) }
            finishRenameCleanup(selecting: newName)
        } catch {
            finishRenameCleanup(selecting: item.name)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Не удалось переименовать «\(item.name)»"
            alert.informativeText = error.localizedDescription
            if let window = view.window {
                alert.beginSheetModal(for: window) { [weak self] _ in self?.focus() }
            }
        }
    }

    private func finishRenameCleanup(selecting name: String) {
        reloadPendingAfterRename = false
        navigate(to: directory, selecting: name, fallbackRow: tableView.selectedRow, reportErrors: false)
        focus()
    }

    /// Потянули за выделенный файл — тащим все выделенные (для невыделенного таблица тащит только его).
    private func dragURLs(forRow row: Int) -> [URL]? {
        guard let clicked = item(at: row), clicked.kind != .parent, marked.contains(clicked.name) else { return nil }
        return items.filter { $0.kind != .parent && marked.contains($0.name) }.map(\.url)
    }

    // MARK: Открыть с помощью

    /// Программы, которые умеют открыть все `targets`: по умолчанию — первой, остальные по имени;
    /// в конце — «Другая программа…».
    func openWithItems(for targets: [FileItem]) -> [NSMenuItem] {
        let urls = targets.map(\.url)
        guard let first = urls.first else { return [] }
        let workspace = NSWorkspace.shared

        var candidates = workspace.urlsForApplications(toOpen: first)
        for url in urls.dropFirst() {
            let supported = Set(workspace.urlsForApplications(toOpen: url).map(\.standardizedFileURL))
            candidates = candidates.filter { supported.contains($0.standardizedFileURL) }
        }
        let defaultApp = workspace.urlForApplication(toOpen: first)?.standardizedFileURL

        // Одна программа может лежать в нескольких местах — оставляем одну (по bundle id).
        var seen = Set<String>()
        var apps: [(url: URL, name: String, isDefault: Bool)] = []
        for url in candidates {
            let key = Bundle(url: url)?.bundleIdentifier ?? url.path
            guard seen.insert(key).inserted else { continue }
            let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            apps.append((url, name, url.standardizedFileURL == defaultApp))
        }
        apps.sort { a, b in
            if a.isDefault != b.isDefault { return a.isDefault }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        var items: [NSMenuItem] = apps.map { app in
            let item = ActionMenuItem(app.isDefault ? "\(app.name) (по умолчанию)" : app.name) {
                workspace.open(urls, withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
            }
            let icon = (workspace.icon(forFile: app.url.path).copy() as? NSImage) ?? NSImage()
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            return item
        }
        if items.isEmpty {
            let none = NSMenuItem(title: "Нет подходящих программ", action: nil, keyEquivalent: "")
            none.isEnabled = false
            items.append(none)
        }
        items.append(.separator())
        items.append(ActionMenuItem("Другая программа…") { [weak self] in self?.chooseApplication(for: urls) })
        return items
    }

    private func chooseApplication(for urls: [URL]) {
        let picker = NSOpenPanel()
        picker.message = "Выберите программу, чтобы открыть " + (urls.count == 1 ? "«\(urls[0].lastPathComponent)»" : "\(urls.count) объектов")
        picker.prompt = "Открыть"
        picker.allowedContentTypes = [.application]
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false

        let open = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let app = picker.url else { return }
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
        if let window = view.window {
            picker.beginSheetModal(for: window) { [weak self] response in
                open(response)
                self?.focus()
            }
        } else {
            open(picker.runModal())
        }
    }

    /// Перечитывает папку и ставит курсор на файл (например, только что созданный).
    func select(named name: String) {
        navigate(to: directory, selecting: name, fallbackRow: tableView.selectedRow, reportErrors: false)
    }

    /// Содержимое папки в том виде, как показано (без «..», с учётом скрытых).
    var listedItems: [FileItem] {
        items.filter { $0.kind != .parent }
    }

    /// Заменяет отметки (сравнение папок).
    func replaceMarks(with names: Set<String>) {
        setMarks(names)
    }

    /// Снимает выделение с файлов (например, после успешного копирования).
    func unmark(_ names: Set<String>) {
        setMarks(marked.subtracting(names))
    }

    /// С чем работает операция: выделенные файлы, а если выделения нет — файл под курсором (кроме «..»).
    func operationTargets() -> [FileItem] {
        let markedItems = items.filter { $0.kind != .parent && marked.contains($0.name) }
        if !markedItems.isEmpty { return markedItems }
        if let current = item(at: tableView.selectedRow), current.kind != .parent { return [current] }
        return []
    }

    /// Создаёт папку (можно вложенные: `a/b/c`) и ставит на неё курсор.
    func createDirectory(named name: String) {
        do {
            let created = try FileOperations.createDirectory(named: name, in: directory)
            if created.deletingLastPathComponent().standardizedFileURL == directory {
                navigate(to: directory, selecting: created.lastPathComponent)
            } else {
                reload()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Не удалось создать папку"
            alert.informativeText = error.localizedDescription
            if let window = view.window {
                alert.beginSheetModal(for: window) { [weak self] _ in self?.focus() }
            } else {
                alert.runModal()
            }
        }
    }

    // MARK: - Контекстное меню

    /// «Просмотр  (F3)» — подсказка берётся из текущих горячих клавиш.
    private static func withHint(_ title: String, _ command: PanelCommand) -> String {
        Hotkeys.shared.hint(for: command).map { "\(title)  (\($0))" } ?? title
    }

    /// Правый клик: по выделенному файлу — меню для всех выделенных,
    /// по невыделенному — только для него (курсор переходит на него), по «..» или пустому месту — общее меню.
    private func contextMenu(forRow row: Int) -> NSMenu {
        focus()
        var targets: [FileItem] = []
        if let clicked = item(at: row), clicked.kind != .parent {
            targets = marked.contains(clicked.name)
                ? items.filter { $0.kind != .parent && marked.contains($0.name) }
                : [clicked]
            moveCursor(to: row)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        let countSuffix = targets.count > 1 ? " (\(targets.count))" : ""

        if targets.count == 1, let target = targets.first {
            menu.addItem(ActionMenuItem("Открыть") { [weak self] in self?.open(target) })
            if target.kind == .directory {
                menu.addItem(ActionMenuItem(Self.withHint("Открыть в новой вкладке", .openInNewTab)) { [weak self] in
                    guard let self else { return }
                    self.delegate?.filePanel(self, requestsNewTabWith: target.url)
                })
            }
        }
        if !targets.isEmpty {
            let openWith = NSMenuItem(title: "Открыть с помощью", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            openWithItems(for: targets).forEach(submenu.addItem)
            openWith.submenu = submenu
            menu.addItem(openWith)
        }
        if !targets.isEmpty {
            menu.addItem(ActionMenuItem(Self.withHint("Просмотр", .quickLook)) { [weak self] in self?.togglePreview() })
            menu.addItem(ActionMenuItem(Self.withHint("Редактировать", .edit)) { [weak self] in
                guard let self else { return }
                self.delegate?.filePanel(self, requestsEditOf: targets)
            })
        }
        if !targets.isEmpty {
            menu.addItem(ActionMenuItem("Показать в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
            })
            menu.addItem(ActionMenuItem(targets.count > 1 ? "Скопировать пути" : "Скопировать путь") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(targets.map(\.url.path).joined(separator: "\n"), forType: .string)
            })
            menu.addItem(.separator())
        }

        menu.addItem(ActionMenuItem("Новая папка…") { [weak self] in
            guard let self else { return }
            self.delegate?.filePanelRequestsNewDirectory(self)
        })
        menu.addItem(ActionMenuItem("Новый файл…") { [weak self] in
            guard let self else { return }
            self.delegate?.filePanelRequestsNewFile(self)
        })

        if !targets.isEmpty {
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Копировать в другую панель…" + countSuffix) { [weak self] in
                guard let self else { return }
                self.delegate?.filePanel(self, requestsCopyOf: targets)
            })
            menu.addItem(ActionMenuItem("Переместить в другую панель…" + countSuffix) { [weak self] in
                guard let self else { return }
                self.delegate?.filePanel(self, requestsMoveOf: targets)
            })
            if targets.count == 1 {
                menu.addItem(ActionMenuItem("Переименовать") { [weak self] in self?.beginRename() })
            }
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem(Self.withHint("Упаковать…", .createArchive)) { [weak self] in
                guard let self else { return }
                self.delegate?.filePanel(self, requestsPackOf: targets)
            })
            if targets.contains(where: { $0.kind == .file && ArchiveFormats.isArchive($0.url) }) {
                menu.addItem(ActionMenuItem(Self.withHint("Распаковать сюда", .extractArchive)) { [weak self] in
                    guard let self else { return }
                    self.delegate?.filePanel(self, requestsExtractOf: targets)
                })
            }
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Переместить в Корзину" + countSuffix) { [weak self] in
                guard let self else { return }
                self.delegate?.filePanel(self, requestsDeletionOf: targets, permanently: false)
            })
            menu.addItem(ActionMenuItem("Удалить насовсем…" + countSuffix) { [weak self] in
                guard let self else { return }
                self.delegate?.filePanel(self, requestsDeletionOf: targets, permanently: true)
            })
        }
        return menu
    }

    // MARK: - Отметки

    /// Отмечает или снимает отметку с файлов по маске. Папки — только если `includeDirectories`.
    func mark(matching mask: FileMask, includeDirectories: Bool, marking: Bool) {
        guard !mask.isEmpty else { return }
        var result = marked
        for item in items where item.kind != .parent && mask.matches(item.name) {
            if item.kind == .directory && !includeDirectories { continue }
            if marking { result.insert(item.name) } else { result.remove(item.name) }
        }
        setMarks(result)
    }

    /// Инвертирует отметку у файлов (папки не трогаем — как в Total Commander).
    private func invertMarks() {
        var result = marked
        for item in items where item.kind == .file || item.kind == .package {
            if result.contains(item.name) { result.remove(item.name) } else { result.insert(item.name) }
        }
        setMarks(result)
    }

    /// `measureDirectories` — посчитать размер папки при выделении (Space делает это, ⇧↑/⇧↓ нет).
    private func toggleMark(at row: Int, moveBy delta: Int, measureDirectories: Bool = true) {
        guard let item = item(at: row) else { return }
        if item.kind != .parent {
            if marked.remove(item.name) == nil {
                marked.insert(item.name)
                if measureDirectories, item.kind == .directory || item.kind == .package {
                    computeSize(of: item)
                }
            }
            reloadRow(row)
            updateLabels()
        }
        if delta != 0 { moveCursor(to: row + delta) }
        resetRange(anchor: row)
    }

    private func setMarks(_ names: Set<String>) {
        rangeBase = nil
        guard names != marked else { return }
        marked = names
        reloadVisibleRows()
        updateLabels()
    }

    /// Выделяет диапазон от якоря до `row` (⇧-клик) и ставит туда курсор.
    /// Отметки, сделанные до начала диапазона, сохраняются; при сужении диапазона
    /// строки, вышедшие из него, возвращаются к прежнему состоянию.
    private func extendRange(to row: Int) {
        guard !items.isEmpty else { return }
        let row = min(max(row, 0), items.count - 1)
        let anchor = min(max(rangeAnchor, 0), items.count - 1)
        let base = rangeBase ?? marked
        rangeBase = base

        var result = base
        for index in min(anchor, row)...max(anchor, row) where items[index].kind != .parent {
            result.insert(items[index].name)
        }
        if result != marked {
            marked = result
            reloadVisibleRows()
            updateLabels()
        }

        isExtendingRange = true
        moveCursor(to: row)
        isExtendingRange = false
    }

    private func resetRange(anchor: Int) {
        rangeAnchor = anchor
        rangeBase = nil
    }

    private func computeSize(of item: FileItem) {
        let name = item.name
        guard directorySizes[name] == nil, !sizingInProgress.contains(name) else { return }
        sizingInProgress.insert(name)
        reloadRow(named: name)

        let cancellation = sizingCancellation
        let url = item.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let size = DirectorySize.compute(url, cancellation: cancellation)
            DispatchQueue.main.async {
                guard let self, let size, !cancellation.isCancelled else { return }
                self.sizingInProgress.remove(name)
                self.directorySizes[name] = size
                self.reloadRow(named: name)
                self.updateLabels()
            }
        }
    }

    // MARK: - Вспомогательное

    private var allNames: Set<String> {
        Set(items.filter { $0.kind != .parent }.map(\.name))
    }

    private func item(at row: Int) -> FileItem? {
        row >= 0 && row < items.count ? items[row] : nil
    }

    private func arrange(_ listed: [FileItem]) -> [FileItem] {
        var result = DirectoryLister.sorted(listed, by: sortKey, ascending: sortAscending)
        if directory.path != "/" {
            result.insert(FileItem.parent(of: directory), at: 0)
        }
        return result
    }

    private func moveCursor(to row: Int) {
        guard !items.isEmpty else { return }
        let row = min(max(row, 0), items.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func reloadRow(_ row: Int) {
        guard row >= 0, row < items.count else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    private func reloadRow(named name: String) {
        if let row = items.firstIndex(where: { $0.name == name }) { reloadRow(row) }
    }

    private func reloadVisibleRows() {
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }
        tableView.reloadData(
            forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
            columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
        )
    }

    private func size(of item: FileItem) -> Int64? {
        item.kind == .file ? item.size : directorySizes[item.name]
    }

    private func updateLabels() {
        pathLabel.stringValue = directory.path

        let entries = items.filter { $0.kind != .parent }
        let markedEntries = entries.filter { marked.contains($0.name) }

        if markedEntries.isEmpty {
            let directories = entries.filter { $0.kind == .directory }.count
            let files = entries.count - directories
            let totalSize = entries.reduce(Int64(0)) { $0 + ($1.kind == .file ? ($1.size ?? 0) : 0) }
            statusLabel.stringValue = "Папок: \(directories), файлов: \(files) (\(formatBytes(totalSize)))"
        } else {
            let directories = markedEntries.filter { $0.kind == .directory }.count
            let files = markedEntries.count - directories
            let markedSize = markedEntries.reduce(Int64(0)) { $0 + (size(of: $1) ?? 0) }
            let counting = markedEntries.contains { sizingInProgress.contains($0.name) } ? "…" : ""
            statusLabel.stringValue = "Выделено: \(markedEntries.count) из \(entries.count) "
                + "(папок: \(directories), файлов: \(files)) · \(formatBytes(markedSize))\(counting)"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func showError(_ error: Error, opening url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Не удалось открыть «\(url.lastPathComponent)»"
        alert.informativeText = error.localizedDescription
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

// MARK: - NSTableViewDataSource, NSTableViewDelegate

extension FilePanelViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier, let column = Column(rawValue: identifier.rawValue) else { return nil }
        let item = items[row]
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PanelCellView
            ?? makeCell(identifier: identifier, withImage: column == .name, alignment: column == .size ? .right : .left)

        let text: String
        switch column {
        case .name:
            text = item.displayName
            cell.imageView?.image = IconProvider.icon(for: item)
        case .ext:
            text = item.ext
        case .size:
            switch item.kind {
            case .parent:
                text = ""
            case .directory, .package:
                if let size = directorySizes[item.name] {
                    text = Self.sizeFormatter.string(from: NSNumber(value: size)) ?? ""
                } else {
                    text = sizingInProgress.contains(item.name) ? "…" : "<DIR>"
                }
            case .file:
                text = item.size.flatMap { Self.sizeFormatter.string(from: NSNumber(value: $0)) } ?? ""
            }
        case .modified:
            text = item.modified.map(Self.dateFormatter.string(from:)) ?? ""
        }

        cell.textField?.stringValue = text
        cell.isDimmed = item.isHidden
        cell.isMarked = marked.contains(item.name)
        cell.tint = FileColors.shared.color(for: item)
        return cell
    }

    // MARK: Перетаскивание

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let item = item(at: row), item.kind != .parent else { return nil }
        return item.url as NSURL
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard let urls = Self.fileURLs(in: info), !urls.isEmpty else { return [] }

        // На папку (или «..») — в неё, иначе — в текущую папку панели (подсвечивается вся таблица).
        var target = directory
        if dropOperation == .on, let item = item(at: row), item.isContainer {
            target = item.url.standardizedFileURL
        } else {
            tableView.setDropRow(-1, dropOperation: .on)
        }

        // Сравниваем реальные пути: при перетаскивании macOS может отдать /private/var/… вместо /var/… и т.п.
        let targetPath = target.resolvingSymlinksInPath().path
        let sourcePaths = urls.map { $0.resolvingSymlinksInPath().path }
        if sourcePaths.allSatisfy({ ($0 as NSString).deletingLastPathComponent == targetPath }) { return [] }
        if sourcePaths.contains(where: { targetPath == $0 || targetPath.hasPrefix($0 + "/") }) { return [] }

        let mask = info.draggingSourceOperationMask
        let wantsMove = NSEvent.modifierFlags.contains(.command)
        let operation: NSDragOperation
        if wantsMove, mask.contains(.move) {
            operation = .move
        } else if wantsMove, mask.contains(.generic) {
            operation = .generic
        } else if mask.contains(.copy) {
            operation = .copy
        } else {
            return []
        }
        dropTarget = target
        dropIsMove = operation != .copy
        return operation
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = Self.fileURLs(in: info), !urls.isEmpty, let target = dropTarget else { return false }
        delegate?.filePanel(self, requestsDropOf: urls, into: target, move: dropIsMove)
        dropTarget = nil
        return true
    }

    private static func fileURLs(in info: NSDraggingInfo) -> [URL]? {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key.flatMap(SortKey.init(rawValue:)) else { return }
        guard key != sortKey || descriptor.ascending != sortAscending else { return }

        let cursorName = item(at: tableView.selectedRow)?.name
        sortKey = key
        sortAscending = descriptor.ascending
        items = arrange(items.filter { $0.kind != .parent })
        tableView.reloadData()
        moveCursor(to: cursorName.flatMap { name in items.firstIndex { $0.name == name } } ?? 0)
        resetRange(anchor: tableView.selectedRow)
    }

    /// Курсор сдвинули обычным способом (клик, стрелки, поиск по буквам) — он становится новым якорем диапазона.
    func tableViewSelectionDidChange(_ notification: Notification) {
        if isPreviewController { updatePreviewItems() }
        guard !isExtendingRange else { return }
        resetRange(anchor: tableView.selectedRow)
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard tableColumn?.identifier.rawValue == Column.name.rawValue, items[row].kind != .parent else { return nil }
        return items[row].name
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier, withImage: Bool, alignment: NSTextAlignment) -> PanelCellView {
        let cell = PanelCellView()
        cell.identifier = identifier

        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.alignment = alignment
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField

        var constraints = [
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ]

        if withImage {
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView
            constraints += [
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            ]
        } else {
            constraints.append(textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4))
        }

        NSLayoutConstraint.activate(constraints)
        return cell
    }
}

// MARK: - NSTextFieldDelegate (переименование)

extension FilePanelViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === pathField {
            return pathFieldCommand(commandSelector, textView: textView)
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            renameCancelled = true
            view.window?.makeFirstResponder(tableView)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === pathField {
            endPathEditing()
        } else {
            finishRename(field)
        }
    }
}

// MARK: - Quick Look (F3)

extension FilePanelViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// F3 / ⌘Y: открыть или закрыть просмотр.
    func togglePreview() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        focus()
        guard !computePreviewItems().urls.isEmpty else { return }
        // orderFront, а не makeKey: главное окно остаётся активным, стрелки двигают курсор в панели.
        panel.orderFront(nil)
        panel.updateController()
        QuickLookShareHider.apply(to: panel)
    }

    func closePreview() {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// Курсор на выделенном файле при нескольких выделенных — показываем все выделенные, иначе — файл под курсором.
    private func computePreviewItems() -> (urls: [URL], index: Int) {
        guard let cursor = item(at: tableView.selectedRow), cursor.kind != .parent else { return ([], 0) }
        if marked.contains(cursor.name), marked.count > 1 {
            let markedItems = items.filter { $0.kind != .parent && marked.contains($0.name) }
            return (markedItems.map(\.url), markedItems.firstIndex { $0.name == cursor.name } ?? 0)
        }
        return ([cursor.url], 0)
    }

    /// Просмотр следует за курсором. На «..» оставляем то, что было.
    private func updatePreviewItems() {
        let (urls, index) = computePreviewItems()
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        if urls != previewItems {
            previewItems = urls
            panel.reloadData()
        }
        if panel.currentPreviewItemIndex != index {
            panel.currentPreviewItemIndex = index
        }
        QuickLookShareHider.apply(to: panel)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        isPreviewController = true
        panel.dataSource = self
        panel.delegate = self
        previewItems = []
        updatePreviewItems()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        isPreviewController = false
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewItems[index] as NSURL
    }

    /// Если окно просмотра в фокусе (по нему кликнули) — клавиши всё равно управляют панелью.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        tableView.keyDown(with: event)
        return true
    }

    /// Окно просмотра «вырастает» из иконки файла.
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        guard let url = item.previewItemURL,
              let row = items.firstIndex(where: { $0.url == url }),
              let window = view.window,
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let imageView = cell.imageView else { return .zero }
        let rect = imageView.convert(imageView.bounds, to: nil)
        guard tableView.visibleRect.intersects(tableView.convert(rect, from: nil)) else { return .zero }
        return window.convertToScreen(rect)
    }

    func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        guard let url = item.previewItemURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Навигация: история, ввод пути

extension FilePanelViewController {
    func goBack() {
        while let entry = backStack.popLast() {
            guard FileManager.default.fileExists(atPath: entry.directory.path) else { continue }
            let from = directory
            forwardStack.append(HistoryEntry(directory: directory, cursorName: item(at: tableView.selectedRow)?.name))
            // Возвращаемся в родительскую, а курсор тогда стоял на «..» — ставим его на папку, откуда пришли (как ⌫).
            var cursor = entry.cursorName
            if cursor == nil || cursor == "..", from.deletingLastPathComponent().standardizedFileURL == entry.directory.standardizedFileURL {
                cursor = from.lastPathComponent
            }
            if navigate(to: entry.directory, selecting: cursor, reportErrors: false, recordHistory: false) { return }
        }
        updateHistoryButtons()
        NSSound.beep()
    }

    func goForward() {
        while let entry = forwardStack.popLast() {
            guard FileManager.default.fileExists(atPath: entry.directory.path) else { continue }
            backStack.append(HistoryEntry(directory: directory, cursorName: item(at: tableView.selectedRow)?.name))
            if navigate(to: entry.directory, selecting: entry.cursorName, reportErrors: false, recordHistory: false) { return }
        }
        updateHistoryButtons()
        NSSound.beep()
    }

    private func updateHistoryButtons() {
        backButton.isEnabled = !backStack.isEmpty
        forwardButton.isEnabled = !forwardStack.isEmpty
    }

    @objc private func backClicked() {
        goBack()
        focus()
    }

    @objc private func forwardClicked() {
        goForward()
        focus()
    }

    @objc private func pathLabelClicked() {
        beginPathEditing()
    }

    /// ⌘L / клик по строке пути: путь становится полем ввода.
    func beginPathEditing() {
        pathField.stringValue = directory.path == "/" ? "/" : directory.path + "/"
        pathField.isHidden = false
        pathLabel.isHidden = true
        view.window?.makeFirstResponder(pathField)
        pathField.currentEditor()?.selectAll(nil)
    }

    private func endPathEditing() {
        pathField.isHidden = true
        pathLabel.isHidden = false
    }

    /// Enter — перейти, Esc — отмена, Tab — дополнить имя папки.
    private func pathFieldCommand(_ selector: Selector, textView: NSTextView) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            endPathEditing()
            focus()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if openTypedPath(pathField.stringValue) {
                endPathEditing()
                focus()
            } else {
                NSSound.beep()
            }
            return true
        case #selector(NSResponder.insertTab(_:)):
            if let completed = FilePanelViewController.completePath(textView.string, relativeTo: directory) {
                textView.string = completed
                textView.setSelectedRange(NSRange(location: (completed as NSString).length, length: 0))
            } else {
                NSSound.beep()
            }
            return true
        default:
            return false
        }
    }

    /// Папка — открыть; файл — открыть его папку и поставить на него курсор. Относительные пути — от текущей папки.
    private func openTypedPath(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : directory.appendingPathComponent(expanded)).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue {
            return navigate(to: url)
        }
        return navigate(to: url.deletingLastPathComponent(), selecting: url.lastPathComponent)
    }

    /// Дополнение по Tab: одна подходящая папка — дописываем её имя и «/», несколько — общее начало.
    static func completePath(_ input: String, relativeTo base: URL) -> String? {
        let expanded = (input as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : base.appendingPathComponent(expanded).path
        // Слэш в конце смотрим по набранному: URL.path его отбрасывает.
        let endsWithSlash = input.hasSuffix("/")
        let parent = endsWithSlash ? absolute : (absolute as NSString).deletingLastPathComponent
        let prefix = endsWithSlash ? "" : (absolute as NSString).lastPathComponent

        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent) else { return nil }
        let matches = names
            .filter { $0.lowercased().hasPrefix(prefix.lowercased()) && (prefix.hasPrefix(".") || !$0.hasPrefix(".")) }
            .filter { name in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: (parent as NSString).appendingPathComponent(name), isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let first = matches.first else { return nil }

        // Сохраняем то, что пользователь уже набрал (~/…, относительный путь), меняем только последнюю часть.
        let typedParent = endsWithSlash ? input : (input as NSString).deletingLastPathComponent
        let join = { (name: String) -> String in
            if typedParent.isEmpty { return name }
            return typedParent.hasSuffix("/") ? typedParent + name : typedParent + "/" + name
        }
        if matches.count == 1 {
            return join(first) + "/"
        }
        var common = first
        for name in matches.dropFirst() {
            while !name.lowercased().hasPrefix(common.lowercased()) { common.removeLast() }
        }
        return common.count > prefix.count ? join(common) : nil
    }
}
