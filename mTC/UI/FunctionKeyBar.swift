import AppKit

/// Кнопки F-клавиш внизу окна, как в Total Commander.
/// Ещё не реализованные операции показаны неактивными.
final class FunctionKeyBar: NSView {
    struct Key {
        let title: String
        let action: Selector?
    }

    init(keys: [Key], target: AnyObject) {
        super.init(frame: .zero)

        let buttons = keys.map { key -> NSButton in
            let button = NSButton(title: key.title, target: target, action: key.action)
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.bezelStyle = .flexiblePush
            button.refusesFirstResponder = true
            button.isEnabled = key.action != nil
            return button
        }

        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }
}
