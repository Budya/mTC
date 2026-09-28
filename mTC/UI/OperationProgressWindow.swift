import AppKit

/// Небольшое окно прогресса файловой операции: что делаем, текущий файл, полоса, объём и скорость, «Отмена».
/// Не модальное — с панелями можно работать, пока идёт копирование.
final class OperationProgressWindowController: NSWindowController {
    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let currentLabel = NSTextField(labelWithString: "")
    private let detailsLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Отмена", target: nil, action: nil)
    private var copyStartedAt: Date?

    init(title: String, subtitle: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        super.init(window: panel)

        titleLabel.stringValue = subtitle
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        currentLabel.lineBreakMode = .byTruncatingMiddle
        currentLabel.textColor = .secondaryLabelColor
        currentLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

        progressBar.style = .bar
        progressBar.isIndeterminate = true
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.startAnimation(nil)

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.keyEquivalent = "\u{1b}"

        let content = NSView()
        for subview in [titleLabel, currentLabel, progressBar, detailsLabel, cancelButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            currentLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            currentLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            currentLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            progressBar.topAnchor.constraint(equalTo: currentLabel.bottomAnchor, constant: 8),
            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            detailsLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 6),
            detailsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailsLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -12),

            cancelButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            cancelButton.centerYAnchor.constraint(equalTo: detailsLabel.centerYAnchor),
            cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -14),
        ])
        panel.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    /// Показывает окно по центру над `parent`.
    func show(over parent: NSWindow?) {
        guard let window, !window.isVisible else { return }
        if let parent {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(
                x: frame.midX - window.frame.width / 2,
                y: frame.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }
        showWindow(nil)
    }

    func update(_ progress: CopyOperation.Progress) {
        let bytes = { (value: Int64) in ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }

        if progress.isScanning {
            progressBar.isIndeterminate = true
            progressBar.startAnimation(nil)
            currentLabel.stringValue = "Подсчёт…"
            detailsLabel.stringValue = "файлов: \(progress.totalFiles), \(bytes(progress.totalBytes))"
            return
        }

        if copyStartedAt == nil { copyStartedAt = Date() }
        progressBar.stopAnimation(nil)
        progressBar.isIndeterminate = false
        progressBar.doubleValue = progress.totalBytes > 0
            ? Double(progress.copiedBytes) / Double(progress.totalBytes)
            : Double(progress.copiedFiles) / Double(max(progress.totalFiles, 1))
        currentLabel.stringValue = progress.currentName

        // Число файлов заранее известно не всегда (распаковка) — тогда показываем только сколько уже готово.
        let files = progress.totalFiles > 0 ? "файлов \(progress.copiedFiles) из \(progress.totalFiles)" : "файлов: \(progress.copiedFiles)"
        var details = "\(bytes(progress.copiedBytes)) из \(bytes(progress.totalBytes)) · \(files)"
        if let copyStartedAt, Date().timeIntervalSince(copyStartedAt) > 1 {
            let speed = Double(progress.copiedBytes) / Date().timeIntervalSince(copyStartedAt)
            details += " · \(bytes(Int64(speed)))/с"
        }
        detailsLabel.stringValue = details
    }

    @objc private func cancelClicked() {
        cancelButton.isEnabled = false
        currentLabel.stringValue = "Отмена…"
        onCancel?()
    }
}
