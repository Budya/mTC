import Foundation

/// Какие файлы считаем архивами и как называть папку для распаковки.
enum ArchiveFormats {
    static let extensions: Set<String> = [
        "zip", "jar", "7z", "rar", "tar", "tgz", "gz", "tbz", "tbz2", "bz2", "txz", "xz", "zst", "tzst",
        "iso", "cpio", "xar", "pkg", "cab", "lha", "lzh",
    ]

    /// Спрашивать ли при открытии (Enter / двойной щелчок): установщики и образы дисков открываем как обычно.
    static func asksOnOpen(_ url: URL) -> Bool {
        isArchive(url) && !["pkg", "iso"].contains(url.pathExtension.lowercased())
    }

    static func isArchive(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// Имя без «архивных» расширений: «проект.tar.gz» → «проект».
    static func stem(of url: URL) -> String {
        var name = url.lastPathComponent
        for _ in 0..<2 {
            let ext = (name as NSString).pathExtension.lowercased()
            guard !ext.isEmpty, extensions.contains(ext) else { break }
            name = (name as NSString).deletingPathExtension
        }
        return name.isEmpty ? url.lastPathComponent : name
    }
}

/// Распаковка архивов через системную libarchive — в ту же папку, где лежит архив.
///
/// Архив распаковывается во временную скрытую папку рядом, затем:
/// - один объект верхнего уровня — переносится на место (занято — вопрос, как при копировании);
/// - несколько — временная папка становится папкой с именем архива (занято — с номером).
/// При отмене или ошибке временная папка удаляется. Элементы с `..` или абсолютным путём пропускаются.
/// Для зашифрованных архивов спрашивается пароль (`askPassword`).
///
/// Колбэки вызываются на главном потоке.
final class ArchiveExtractOperation: @unchecked Sendable {
    struct Result {
        /// Архивы, распакованные целиком.
        var completedArchives: [URL] = []
        /// Что появилось в папке (папка или файл верхнего уровня) — на это ставится курсор.
        var created: [URL] = []
        var failures: [(url: URL, error: Error)] = []
        var cancelled = false
    }

    let archives: [URL]

    var onProgress: ((CopyOperation.Progress) -> Void)?
    var resolveConflict: ((CopyOperation.Conflict, @escaping (CopyOperation.ConflictChoice, Bool) -> Void) -> Void)?
    /// Имя архива, была ли уже неудачная попытка → пароль или `nil` (отмена).
    var askPassword: ((String, Bool, @escaping (String?) -> Void) -> Void)?
    var onFinish: ((Result) -> Void)?

    private let cancellation = CancellationFlag()
    private var progress = CopyOperation.Progress()
    private var result = Result()
    private var rememberedChoice: CopyOperation.ConflictChoice?
    private var lastReport = Date.distantPast

    private var currentArchiveName = ""
    private var passwordAttempts = 0
    private var lastPassword: String?
    /// libarchive хранит указатель на строку пароля — держим её живой до следующего запроса.
    private var passwordStorage: UnsafeMutablePointer<CChar>?

    init(archives: [URL]) {
        self.archives = archives
    }

    deinit {
        free(passwordStorage)
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            run()
            report(force: true)
            let result = result
            DispatchQueue.main.async { self.onFinish?(result) }
        }
    }

    func cancel() {
        cancellation.cancel()
    }

    // MARK: - Выполнение

    private func run() {
        progress.isScanning = false
        progress.totalBytes = archives.reduce(0) { $0 + Self.fileSize($1) }
        report(force: true)

        for archive in archives {
            if cancellation.isCancelled { break }
            let before = progress.copiedBytes
            if extract(archive) {
                result.completedArchives.append(archive)
            }
            if !cancellation.isCancelled {
                progress.copiedBytes = before + Self.fileSize(archive)
            }
        }
        result.cancelled = cancellation.isCancelled
    }

    private func extract(_ archiveURL: URL) -> Bool {
        let parent = archiveURL.deletingLastPathComponent()
        let temp = parent.appendingPathComponent(".mtc-extract-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
        } catch {
            result.failures.append((archiveURL, error))
            return false
        }
        defer { try? FileManager.default.removeItem(at: temp) }

        guard unpack(archiveURL, into: temp), !cancellation.isCancelled else { return false }
        return place(from: temp, archive: archiveURL, into: parent)
    }

    /// Распаковывает содержимое архива в `temp`. Возвращает `false` при фатальной ошибке или отмене.
    private func unpack(_ archiveURL: URL, into temp: URL) -> Bool {
        guard let archive = archive_read_new() else { return false }
        defer { archive_read_free(archive) }

        archive_read_support_filter_all(archive)
        archive_read_support_format_all(archive)
        // Одиночный сжатый файл (не tar): «отчёт.txt.gz» → «отчёт.txt».
        archive_read_support_format_raw(archive)

        currentArchiveName = archiveURL.lastPathComponent
        passwordAttempts = 0
        if let lastPassword { archive_read_add_passphrase(archive, lastPassword) }
        archive_read_set_passphrase_callback(archive, Unmanaged.passUnretained(self).toOpaque()) { _, context in
            guard let context else { return nil }
            return UnsafePointer(Unmanaged<ArchiveExtractOperation>.fromOpaque(context).takeUnretainedValue().requestPassword())
        }

        guard archive_read_open_filename(archive, archiveURL.path, 64 * 1024) == ARCHIVE_OK else {
            result.failures.append((archiveURL, Self.error(archive, fallback: "Не удалось открыть архив")))
            return false
        }

        let tempRoot = temp.resolvingSymlinksInPath().path
        var directories: [(URL, Date)] = []
        var entry: OpaquePointer?
        var skippedUnsafe = 0

        while !cancellation.isCancelled {
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            guard status >= ARCHIVE_WARN, let entry else {
                result.failures.append((archiveURL, Self.error(archive, fallback: "Архив повреждён")))
                return false
            }

            guard var components = Self.safeComponents(archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)) else {
                skippedUnsafe += 1
                archive_read_data_skip(archive)
                continue
            }
            // Одиночный сжатый файл libarchive называет «data».
            if components == ["data"], String(cString: archive_format_name(archive)) == "raw" {
                components = [ArchiveFormats.stem(of: archiveURL)]
            }

            let target = components.reduce(temp) { $0.appendingPathComponent($1) }
            let modified = Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
            let type = archive_entry_filetype(entry) & AE_IFMT

            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Защита от «выпрыгивания» через символические ссылки из самого архива.
                guard target.deletingLastPathComponent().resolvingSymlinksInPath().path.hasPrefix(tempRoot) else {
                    skippedUnsafe += 1
                    archive_read_data_skip(archive)
                    continue
                }

                if type == AE_IFDIR {
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    directories.append((target, modified))
                } else if type == AE_IFLNK, let link = archive_entry_symlink_utf8(entry) ?? archive_entry_symlink(entry) {
                    try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: String(cString: link))
                } else if let hardlink = archive_entry_hardlink(entry) {
                    // Жёсткая ссылка на уже распакованный файл — делаем копию.
                    if let source = Self.safeComponents(hardlink)?.reduce(temp, { $0.appendingPathComponent($1) }) {
                        try FileManager.default.copyItem(at: source, to: target)
                    }
                } else {
                    try writeData(of: archive, to: target, archiveURL: archiveURL)
                    try? FileManager.default.setAttributes([
                        .modificationDate: modified,
                        .posixPermissions: NSNumber(value: Int16(archive_entry_perm(entry) & 0o777) | 0o600),
                    ], ofItemAtPath: target.path)
                    progress.copiedFiles += 1
                }
            } catch {
                if cancellation.isCancelled { return false }
                result.failures.append((target, error))
                if result.failures.count > 100 { return false }
            }
        }

        for (directory, date) in directories.reversed() {
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: directory.path)
        }
        if skippedUnsafe > 0 {
            result.failures.append((archiveURL, FileOperationError.unsafeArchiveEntries(skippedUnsafe)))
        }
        return !cancellation.isCancelled
    }

    private func writeData(of archive: OpaquePointer, to target: URL, archiveURL: URL) throws {
        progress.currentName = target.lastPathComponent
        let before = progressBase(for: archiveURL)
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
        }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }

        var buffer: UnsafeRawPointer?
        var size = 0
        var offset: Int64 = 0
        while true {
            if cancellation.isCancelled {
                try? FileManager.default.removeItem(at: target)
                throw CocoaError(.userCancelled)
            }
            let status = archive_read_data_block(archive, &buffer, &size, &offset)
            if status == ARCHIVE_EOF { break }
            guard status >= ARCHIVE_WARN else {
                try? FileManager.default.removeItem(at: target)
                throw Self.error(archive, fallback: "Не удалось прочитать данные")
            }
            if let buffer, size > 0 {
                try handle.seek(toOffset: UInt64(offset))
                try handle.write(contentsOf: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: buffer), count: size, deallocator: .none))
            }
            progress.copiedBytes = before + archive_filter_bytes(archive, -1)
            report(force: false)
        }
    }

    /// Сколько байт уже «сделано» до текущего архива (для полосы прогресса).
    private func progressBase(for archiveURL: URL) -> Int64 {
        var total: Int64 = 0
        for archive in archives {
            if archive == archiveURL { break }
            total += Self.fileSize(archive)
        }
        return total
    }

    /// Ставит распакованное на место. Возвращает `true`, если что-то появилось в папке.
    private func place(from temp: URL, archive: URL, into parent: URL) -> Bool {
        let items = (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? []
        guard !items.isEmpty else { return true }

        if items.count == 1, let single = items.first {
            var destination = parent.appendingPathComponent(single.lastPathComponent)
            if Self.exists(destination) {
                switch choice(for: CopyOperation.Conflict(source: single, destination: destination)) {
                case .skip:
                    return false
                case .cancel:
                    cancellation.cancel()
                    return false
                case .keepBoth:
                    destination = FileOperations.uniqueURL(for: destination, isDirectory: Self.isDirectory(single))
                case .replace:
                    do { try FileManager.default.removeItem(at: destination) } catch {
                        result.failures.append((destination, error))
                        return false
                    }
                }
            }
            return move(single, to: destination)
        }

        let folder = FileOperations.uniqueURL(for: parent.appendingPathComponent(ArchiveFormats.stem(of: archive)), isDirectory: true)
        return move(temp, to: folder)
    }

    private func move(_ source: URL, to destination: URL) -> Bool {
        if rename(source.path, destination.path) != 0 {
            result.failures.append((destination, POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)))
            return false
        }
        result.created.append(destination)
        return true
    }

    // MARK: - Вопросы пользователю

    private func choice(for conflict: CopyOperation.Conflict) -> CopyOperation.ConflictChoice {
        if let rememberedChoice { return rememberedChoice }
        guard let resolveConflict else { return .skip }
        let semaphore = DispatchSemaphore(value: 0)
        var answer: (CopyOperation.ConflictChoice, Bool) = (.cancel, false)
        DispatchQueue.main.async {
            resolveConflict(conflict) { choice, applyToAll in
                answer = (choice, applyToAll)
                semaphore.signal()
            }
        }
        semaphore.wait()
        if answer.1 && answer.0 != .cancel { rememberedChoice = answer.0 }
        return answer.0
    }

    /// Вызывается из libarchive, когда нужен пароль (и повторно — если предыдущий не подошёл).
    private func requestPassword() -> UnsafeMutablePointer<CChar>? {
        guard let askPassword, !cancellation.isCancelled else { return nil }
        passwordAttempts += 1
        let semaphore = DispatchSemaphore(value: 0)
        var password: String?
        let name = currentArchiveName
        let retry = passwordAttempts > 1
        DispatchQueue.main.async {
            askPassword(name, retry) { value in
                password = value
                semaphore.signal()
            }
        }
        semaphore.wait()

        free(passwordStorage)
        passwordStorage = nil
        guard let password else {
            cancellation.cancel()
            return nil
        }
        lastPassword = password
        passwordStorage = strdup(password)
        return passwordStorage
    }

    // MARK: - Вспомогательное

    private func report(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) > 0.1 else { return }
        lastReport = now
        let snapshot = progress
        DispatchQueue.main.async { [weak self] in self?.onProgress?(snapshot) }
    }

    /// Путь элемента без «.», пустых частей и ведущего «/»; `nil`, если в нём есть «..».
    private static func safeComponents(_ path: UnsafePointer<CChar>?) -> [String]? {
        guard let path else { return nil }
        let components = String(cString: path).split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        guard !components.isEmpty, !components.contains("..") else { return nil }
        return components
    }

    private static func error(_ archive: OpaquePointer, fallback: String) -> Error {
        let message = archive_error_string(archive).map { String(cString: $0) } ?? fallback
        return NSError(domain: "mTC.archive", code: Int(archive_errno(archive)), userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func fileSize(_ url: URL) -> Int64 {
        var info = stat()
        return lstat(url.path, &info) == 0 ? Int64(info.st_size) : 0
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }
}
