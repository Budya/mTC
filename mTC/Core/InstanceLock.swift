import Foundation

/// Эксклюзивная блокировка папки настроек (`mTC-data/.lock`), чтобы две копии mTC,
/// запущенные с одной папкой (например, с общей шары), не перетирали настройки друг друга.
/// Блокировка снимается автоматически при завершении процесса.
final class InstanceLock {
    private let descriptor: Int32

    init?(directory: URL) {
        let path = directory.appendingPathComponent(".lock").path
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
