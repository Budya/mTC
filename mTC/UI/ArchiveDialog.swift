import AppKit

/// Содержимое диалога «Упаковать…»: имя, формат, пароль и шифрование (только zip), куда положить.
final class ArchiveDialog: NSObject {
    let view: NSView
    let nameField = NSTextField(string: "")
    let passwordField = NSSecureTextField(string: "")
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let encryptionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let passwordNote = NSTextField(wrappingLabelWithString: "")
    private let otherPanelCheckbox = NSButton(checkboxWithTitle: "Положить в папку другой панели:", target: nil, action: nil)
    /// Путь другой панели — отдельной строкой с переносом, чтобы длинный путь был виден целиком.
    private let otherPanelPathLabel = NSTextField(wrappingLabelWithString: "")

    var kind: ArchiveKind {
        ArchiveKind.allCases[max(formatPopup.indexOfSelectedItem, 0)]
    }

    var encryption: ZipEncryption {
        ZipEncryption.allCases[max(encryptionPopup.indexOfSelectedItem, 0)]
    }

    var toOtherPanel: Bool {
        otherPanelCheckbox.state == .on
    }

    init(baseName: String, kind: ArchiveKind, encryption: ZipEncryption, toOtherPanel: Bool, otherPanelPath: String) {
        otherPanelCheckbox.state = toOtherPanel ? .on : .off
        // Перенос по символам (в путях часто нет пробелов).
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        let pathText = NSAttributedString(string: otherPanelPath, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        otherPanelPathLabel.attributedStringValue = pathText
        otherPanelPathLabel.maximumNumberOfLines = 0
        otherPanelPathLabel.heightAnchor.constraint(equalToConstant: Self.wrappedHeight(of: otherPanelPathLabel)).isActive = true

        formatPopup.addItems(withTitles: ArchiveKind.allCases.map(\.title))
        formatPopup.selectItem(at: ArchiveKind.allCases.firstIndex(of: kind) ?? 0)
        encryptionPopup.addItems(withTitles: ZipEncryption.allCases.map(\.title))
        encryptionPopup.selectItem(at: ZipEncryption.allCases.firstIndex(of: encryption) ?? 0)
        nameField.stringValue = baseName + "." + kind.fileExtension
        passwordField.placeholderString = "без пароля"
        passwordNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        passwordNote.textColor = .secondaryLabelColor
        // Высота — под самую длинную подсказку, чтобы окно не прыгало при смене шифрования.
        passwordNote.maximumNumberOfLines = 0
        let note = passwordNote
        let noteHeight = (ZipEncryption.allCases.map(Self.note(for:)) + ["Пароль доступен только для ZIP."]).map {
            note.stringValue = $0
            return Self.wrappedHeight(of: note)
        }.max() ?? 0
        passwordNote.heightAnchor.constraint(equalToConstant: noteHeight).isActive = true
        // Без заданной ширины переноса поле рисует текст по старой раскладке, пока по нему не щёлкнуть.
        for label in [passwordNote, otherPanelPathLabel] {
            label.preferredMaxLayoutWidth = 300
            label.isSelectable = false
        }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Имя:"), nameField],
            [NSTextField(labelWithString: "Формат:"), formatPopup],
            [NSTextField(labelWithString: "Пароль:"), passwordField],
            [NSTextField(labelWithString: "Шифрование:"), encryptionPopup],
            [NSGridCell.emptyContentView, passwordNote],
            [NSGridCell.emptyContentView, otherPanelCheckbox],
            [NSGridCell.emptyContentView, otherPanelPathLabel],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.row(at: 0).yPlacement = .center
        grid.row(at: 2).yPlacement = .center
        for field in [nameField, passwordField] as [NSTextField] {
            field.heightAnchor.constraint(equalToConstant: 24).isActive = true
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
            field.lineBreakMode = .byTruncatingMiddle
            field.cell?.isScrollable = true
        }
        nameField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        passwordField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        passwordNote.widthAnchor.constraint(equalToConstant: 300).isActive = true
        otherPanelPathLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
        grid.row(at: 6).topPadding = -4
        // NSAlert берёт размер вспомогательной области из рамки — считаем её по содержимому.
        grid.layoutSubtreeIfNeeded()
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)
        view = grid

        super.init()
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        encryptionPopup.target = self
        encryptionPopup.action = #selector(encryptionChanged)
        updatePassword()
    }

    /// Смена формата — меняем расширение в имени и доступность пароля.
    @objc private func formatChanged() {
        let base = ArchiveKind.stripExtension(nameField.stringValue)
        nameField.stringValue = base + "." + kind.fileExtension
        updatePassword()
    }

    @objc private func encryptionChanged() {
        updatePassword()
    }

    private func updatePassword() {
        passwordField.isEnabled = kind.supportsPassword
        encryptionPopup.isEnabled = kind.supportsPassword
        guard kind.supportsPassword else {
            passwordNote.stringValue = "Пароль доступен только для ZIP."
            return
        }
        passwordNote.stringValue = Self.note(for: encryption)
    }

    /// Высота многострочной подписи шириной `labelWidth`. Считаем сами: сетка иначе даёт одну строку.
    /// Меряем ячейкой поля, а не строкой, — у ячейки свои отступы и перенос.
    private static let labelWidth: CGFloat = 300

    private static func wrappedHeight(of label: NSTextField) -> CGFloat {
        ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: labelWidth, height: 10_000)).height ?? 0)
    }

    private static func note(for encryption: ZipEncryption) -> String {
        switch encryption {
        case .zipCrypto:
            return "Откроется где угодно, в том числе двойным щелчком в Finder. Защита слабая: от случайных глаз, не от взлома."
        case .aes256:
            return "Надёжная защита, но двойным щелчком в Finder такой архив не открыть — нужен mTC, 7-Zip или Keka."
        }
    }
}
