import AppKit
import Quartz

/// Убирает кнопку «Поделиться» из окна просмотра (F3).
///
/// Настройки для этого у `QLPreviewPanel` нет: кнопку находим по идентификатору `QLControlShare`
/// и скрываем. Панель сама показывает её снова при смене файла, поэтому следим за `isHidden`
/// и скрываем обратно. Если Apple поменяет устройство панели, кнопка просто останется — ничего не сломается.
enum QuickLookShareHider {
    private static let identifier = "QLControlShare"
    private static var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    /// Вызывать после показа панели и после смены файлов в ней.
    static func apply(to panel: QLPreviewPanel) {
        // Кнопки появляются не сразу после показа — пробуем сейчас и чуть позже.
        hide(in: panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { hide(in: panel) }
    }

    private static func hide(in panel: QLPreviewPanel) {
        guard let root = panel.contentView?.superview else { return }
        for button in shareButtons(in: root) {
            button.isHidden = true
            let key = ObjectIdentifier(button)
            guard observations[key] == nil else { continue }
            observations[key] = button.observe(\.isHidden, options: [.new]) { view, _ in
                if !view.isHidden { view.isHidden = true }
            }
        }
    }

    private static func shareButtons(in view: NSView) -> [NSView] {
        (view.identifier?.rawValue == identifier ? [view] : []) + view.subviews.flatMap(shareButtons)
    }
}
