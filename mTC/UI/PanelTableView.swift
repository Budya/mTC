import AppKit

/// Таблица панели с клавиатурой в стиле Total Commander.
/// Выделение строк таблицы используется как курсор (одна строка),
/// а отмеченные файлы хранит панель.
final class PanelTableView: NSTableView {
    var onCommand: ((PanelCommand) -> Void)?
    /// ⌘-клик: отметить/снять отметку со строки.
    var onToggleMarkAtRow: ((Int) -> Void)?
    /// ⇧-клик: выделить диапазон от якоря до строки.
    var onExtendRangeToRow: ((Int) -> Void)?
    /// Правый клик / ⌃-клик: меню для строки (`-1` — пустое место).
    var onContextMenu: ((Int) -> NSMenu?)?
    /// Что тащить, если потянуть за строку: для выделенного файла — все выделенные.
    /// `nil` или один файл — обычное перетаскивание строки таблицей.
    var dragURLsForRow: ((Int) -> [URL]?)?
    var onFocus: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if let command = PanelKeyMap.command(for: event) {
            onCommand?(command)
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift])
        guard !modifiers.isEmpty else {
            if event.clickCount == 1, !dragMarkedFiles(from: event) {
                super.mouseDown(with: event)
            } else if event.clickCount > 1 {
                super.mouseDown(with: event)
            }
            return
        }
        let clickedRow = row(at: convert(event.locationInWindow, from: nil))
        window?.makeFirstResponder(self)
        guard clickedRow >= 0 else { return }
        if modifiers == .shift {
            onExtendRangeToRow?(clickedRow)
        } else {
            onToggleMarkAtRow?(clickedRow)
        }
    }

    /// Нажали на выделенный файл, когда выделено несколько: ждём, потянут или просто кликнут.
    /// Потянули — тащим все выделенные; отпустили — ставим курсор на строку. Возвращает `false`,
    /// если этот случай не наш и нажатие надо отдать таблице.
    private func dragMarkedFiles(from event: NSEvent) -> Bool {
        let clickedRow = row(at: convert(event.locationInWindow, from: nil))
        guard clickedRow >= 0, let urls = dragURLsForRow?(clickedRow), urls.count > 1, let window else { return false }

        window.makeFirstResponder(self)
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
                return true
            }
            if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 3 {
                beginDragging(urls, event: next)
                return true
            }
        }
        return true
    }

    private func beginDragging(_ urls: [URL], event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(NSRect(x: point.x - 16 + offset, y: point.y - 16 + offset, width: 32, height: 32), contents: icon)
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .pile
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu?(row(at: convert(event.locationInWindow, from: nil)))
    }

    /// «Правка → Выделить всё» (⌘A): выделяет все файлы панели, повторное нажатие снимает выделение.
    override func selectAll(_ sender: Any?) {
        onCommand?(.toggleMarkAll)
    }

    /// NSTableView отключает «Выделить всё», когда `allowsMultipleSelection == false`,
    /// а у нас строка таблицы — только курсор, и отметки живут отдельно.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(selectAll(_:)) { return true }
        return super.validateUserInterfaceItem(item)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}

/// Ячейка, которая знает, отмечен ли файл, и подбирает цвет текста
/// в том числе на подсвеченной строке курсора.
final class PanelCellView: NSTableCellView {
    var isMarked = false { didSet { updateAppearance() } }
    var isDimmed = false { didSet { updateAppearance() } }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateAppearance() }
    }

    private func updateAppearance() {
        guard let textField else { return }
        if backgroundStyle == .emphasized {
            // На синей подсветке курсора красный не читается — выделенный файл под курсором жёлтый.
            textField.textColor = isMarked ? .systemYellow : .alternateSelectedControlTextColor
        } else if isMarked {
            textField.textColor = .systemRed
        } else {
            textField.textColor = isDimmed ? .secondaryLabelColor : .labelColor
        }
        textField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: isMarked ? .semibold : .regular)
    }
}
