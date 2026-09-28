import CoreServices
import Foundation

/// Следит за изменениями в одной папке через FSEvents и вызывает `onChange` на главном потоке.
///
/// - Реагирует только на изменения непосредственно в папке (создание, удаление, переименование,
///   изменение файлов), изменения во вложенных папках игнорируются.
/// - Сообщает и о том, что саму папку удалили или переименовали (`WatchRoot`).
/// - События за `latency` секунд склеиваются в один вызов.
/// - Изменения, сделанные на сетевых дисках с других компьютеров, FSEvents не видит.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let watchedPath: String
    private let onChange: () -> Void

    init?(url: URL, latency: TimeInterval = 0.3, onChange: @escaping () -> Void) {
        // FSEvents присылает реальные пути (/private/tmp вместо /tmp), поэтому сравниваем с realpath.
        guard let resolved = realpath(url.path, nil) else { return nil }
        watchedPath = Self.normalized(String(cString: resolved))
        free(resolved)
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            let flags = (0..<count).map { eventFlags[$0] }
            watcher.handle(paths: paths, flags: flags)
        }

        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [watchedPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else { return nil }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        let relevant = zip(paths, flags).contains { path, flag in
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMustScanSubDirs) != 0 {
                return true
            }
            return Self.normalized(path).caseInsensitiveCompare(watchedPath) == .orderedSame
        }
        if relevant { onChange() }
    }

    private static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
