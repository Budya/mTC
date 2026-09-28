import AppKit

/// Строка над панелью: выбор диска (тома) и свободное место на нём.
final class DriveBar: NSView {
    enum Choice {
        case volume(Volume)
        case home
        case root
    }

    var onSelect: ((Choice) -> Void)?

    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let capacityLabel = NSTextField(labelWithString: "")
    private var volumes: [Volume] = []

    private static let homeTag = -1
    private static let rootTag = -2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        popup.controlSize = .small
        popup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        popup.bezelStyle = .flexiblePush
        popup.refusesFirstResponder = true
        popup.target = self
        popup.action = #selector(selectionChanged)

        capacityLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        capacityLabel.textColor = .secondaryLabelColor
        capacityLabel.lineBreakMode = .byTruncatingTail
        capacityLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for subview in [popup, capacityLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            popup.centerYAnchor.constraint(equalTo: centerYAnchor),
            popup.widthAnchor.constraint(lessThanOrEqualToConstant: 220),

            capacityLabel.leadingAnchor.constraint(equalTo: popup.trailingAnchor, constant: 8),
            capacityLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            capacityLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    /// Перестраивает список томов и показывает, где сейчас панель:
    /// «Home» внутри неё, «Root» в самом `/`, иначе — том папки.
    func update(volumes: [Volume], directory: URL, capacity: VolumeCapacity?) {
        if volumes != self.volumes || popup.menu?.items.isEmpty != false {
            self.volumes = volumes
            rebuildMenu()
        }

        let path = directory.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let volume = Volumes.volumeURL(containing: directory)

        if path == home || path.hasPrefix(home + "/") {
            popup.selectItem(withTag: Self.homeTag)
        } else if path == "/" {
            popup.selectItem(withTag: Self.rootTag)
        } else if let volume, let index = volumes.firstIndex(where: { $0.url == volume }) {
            popup.selectItem(withTag: index)
        } else {
            popup.select(nil)
        }

        if let capacity {
            let available = ByteCountFormatter.string(fromByteCount: capacity.available, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: capacity.total, countStyle: .file)
            capacityLabel.stringValue = "свободно \(available) из \(total)"
        } else {
            capacityLabel.stringValue = ""
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        for (index, volume) in volumes.enumerated() {
            let item = NSMenuItem(title: volume.name, action: nil, keyEquivalent: "")
            item.image = Volumes.icon(for: volume)
            item.tag = index
            item.toolTip = volume.url.path
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let home = NSMenuItem(title: "Home", action: nil, keyEquivalent: "")
        home.image = NSImage(systemSymbolName: "house", accessibilityDescription: nil)
        home.tag = Self.homeTag
        menu.addItem(home)

        let root = NSMenuItem(title: "Root", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: nil)
        root.tag = Self.rootTag
        menu.addItem(root)

        popup.menu = menu
    }

    @objc private func selectionChanged() {
        guard let item = popup.selectedItem else { return }
        if item.tag == Self.homeTag {
            onSelect?(.home)
        } else if item.tag == Self.rootTag {
            onSelect?(.root)
        } else if volumes.indices.contains(item.tag) {
            onSelect?(.volume(volumes[item.tag]))
        }
    }
}
