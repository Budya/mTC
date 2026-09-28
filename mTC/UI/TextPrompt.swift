import AppKit

/// Простой диалог-лист с одним полем ввода.
enum TextPrompt {
    static func present(
        on window: NSWindow,
        title: String,
        message: String,
        defaultValue: String,
        okTitle: String,
        completion: @escaping (String?) -> Void
    ) {
        guard window.attachedSheet == nil else { return }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message

        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: okTitle)
        alert.addCancelButton()
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }
}

extension NSAlert {
    /// Кнопка «Отмена», закрывающая диалог по Esc.
    /// NSAlert сам назначает Esc только кнопке с английским заголовком «Cancel».
    @discardableResult
    func addCancelButton(title: String = "Отмена") -> NSButton {
        let button = addButton(withTitle: title)
        button.keyEquivalent = "\u{1b}"
        return button
    }
}
