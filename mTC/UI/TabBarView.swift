import AppKit

/// Строка вкладок над панелью.
/// Клик — переключить, крестик или средняя кнопка — закрыть, правый клик — меню,
/// двойной клик по пустому месту — новая вкладка.
final class TabBarView: NSView {
    struct Tab {
        let title: String
        let toolTip: String
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onCloseOthers: ((Int) -> Void)?
    var onNewTab: (() -> Void)?

    var isActivePanel = false {
        didSet { tabViews.forEach { $0.isActivePanel = isActivePanel } }
    }

    private var tabViews: [TabItemView] = []
    private static let maxTabWidth: CGFloat = 200

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 26)
    }

    func update(tabs: [Tab], selected: Int) {
        while tabViews.count < tabs.count {
            let view = TabItemView()
            view.onSelect = { [weak self] index in self?.onSelect?(index) }
            view.onClose = { [weak self] index in self?.onClose?(index) }
            view.onCloseOthers = { [weak self] index in self?.onCloseOthers?(index) }
            addSubview(view)
            tabViews.append(view)
        }
        while tabViews.count > tabs.count {
            tabViews.removeLast().removeFromSuperview()
        }

        for (index, tab) in tabs.enumerated() {
            let view = tabViews[index]
            view.index = index
            view.title = tab.title
            view.toolTip = tab.toolTip
            view.isSelected = index == selected
            view.isActivePanel = isActivePanel
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard !tabViews.isEmpty else { return }
        let width = min(Self.maxTabWidth, (bounds.width - 4) / CGFloat(tabViews.count))
        for (index, view) in tabViews.enumerated() {
            view.frame = NSRect(x: 2 + CGFloat(index) * width, y: 3, width: width, height: bounds.height - 3)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onNewTab?() }
    }
}

private final class TabItemView: NSView {
    var index = 0
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onCloseOthers: ((Int) -> Void)?

    var title = "" {
        didSet { label.stringValue = title }
    }

    var isSelected = false {
        didSet { updateAppearance() }
    }

    var isActivePanel = false {
        didSet { needsDisplay = true }
    }

    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var isHovered = false {
        didSet { updateAppearance() }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center

        let symbol = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Закрыть вкладку")?
            .withSymbolConfiguration(symbol)
        closeButton.isBordered = false
        closeButton.refusesFirstResponder = true
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Закрыть вкладку"

        for subview in [closeButton, label] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14),

            label.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?(index) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Закрыть вкладку", action: #selector(closeClicked), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Закрыть другие вкладки", action: #selector(closeOthersClicked), keyEquivalent: "").target = self
        return menu
    }

    @objc private func closeClicked() { onClose?(index) }
    @objc private func closeOthersClicked() { onCloseOthers?(index) }

    private func updateAppearance() {
        closeButton.isHidden = !(isSelected || isHovered)
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            // Нижние углы уходят за край, чтобы вкладка «сливалась» с панелью.
            let shape = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: bounds.height + 6), xRadius: 5, yRadius: 5)
            NSColor.controlBackgroundColor.setFill()
            shape.fill()
            NSColor.separatorColor.setStroke()
            shape.stroke()
            if isActivePanel {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: 6, y: 1, width: bounds.width - 12, height: 2), xRadius: 1, yRadius: 1).fill()
            }
        } else {
            if isHovered {
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
            }
            NSColor.separatorColor.setFill()
            NSRect(x: bounds.width - 1, y: 6, width: 1, height: bounds.height - 12).fill()
        }
    }
}
