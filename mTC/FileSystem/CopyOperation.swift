import Foundation

/// Копирование файлов и папок в фоне: прогресс, отмена, конфликты имён.
///
/// - Файлы копируются через `copyfile(3)` вместе с атрибутами и расширенными атрибутами;
///   на APFS в пределах одного тома — мгновенным клонированием.
/// - Символические ссылки копируются как ссылки.
/// - Папка в папку с тем же именем сливается без вопросов, конфликтом считаются только файлы
///   (и несовпадение типов: файл против папки).
/// - «Заменить» для файла: сначала копия во временный файл рядом, потом подмена —
///   если копирование сорвётся, старый файл останется целым.
/// - Копирование файла самого в себя (та же папка) создаёт дубликат с номером: «файл 2.txt».
///
/// Перемещение (`mode == .move`): в пределах одного тома — мгновенное переименование (папки с одинаковым
/// именем сливаются, конфликты файлов — те же вопросы); на другой том — копирование и удаление источника,
/// только если он скопирован целиком.
///
/// Колбэки `onProgress`, `resolveConflict`, `onFinish` вызываются на главном потоке.
final class CopyOperation: @unchecked Sendable {
    enum Mode {
        case copy, move
    }

    enum Destination {
        /// Скопировать внутрь папки под прежними именами.
        case into(URL)
        /// Один источник — под новым полным путём.
        case renamed(URL)
    }

    enum ConflictChoice {
        case replace, skip, keepBoth, cancel
    }

    struct Conflict {
        let source: URL
        let destination: URL
    }

    struct Progress {
        var isScanning = true
        var totalBytes: Int64 = 0
        var copiedBytes: Int64 = 0
        var totalFiles = 0
        var copiedFiles = 0
        var currentName = ""
    }

    struct Result {
        /// Верхнеуровневые источники, скопированные полностью.
        var completedSources: [URL] = []
        var failures: [(url: URL, error: Error)] = []
        var cancelled = false
    }

    let sources: [URL]
    let destination: Destination
    let mode: Mode
    /// Источники, которые перемещаются переименованием (тот же том) — их не нужно сканировать.
    private var renameSources: Set<URL> = []

    var onProgress: ((Progress) -> Void)?
    /// Вызывается, когда цель уже существует. Второй элемент — «применить ко всем».
    var resolveConflict: ((Conflict, @escaping (ConflictChoice, Bool) -> Void) -> Void)?
    var onFinish: ((Result) -> Void)?

    private let cancellation = CancellationFlag()
    private var progress = Progress()
    private var result = Result()
    private var rememberedChoice: ConflictChoice?
    private var bytesBeforeCurrentFile: Int64 = 0
    private var lastProgressReport = Date.distantPast

    init(sources: [URL], destination: Destination, mode: Mode = .copy) {
        self.sources = sources
        self.destination = destination
        self.mode = mode
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            run()
            reportProgress(force: true)
            let result = result
            DispatchQueue.main.async { self.onFinish?(result) }
        }
    }

    func cancel() {
        cancellation.cancel()
    }

    // MARK: - Выполнение

    private func run() {
        let targetDirectory: URL
        switch destination {
        case .into(let directory): targetDirectory = directory
        case .renamed(let url): targetDirectory = url.deletingLastPathComponent()
        }
        do {
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        } catch {
            result.failures.append((targetDirectory, error))
            return
        }

        if mode == .move {
            renameSources = Set(sources.filter { Self.sameVolume($0.deletingLastPathComponent(), targetDirectory) })
        }
        scan()
        progress.isScanning = false
        reportProgress(force: true)

        for source in sources {
            if cancellation.isCancelled { break }
            var target: URL
            switch destination {
            case .into(let directory): target = directory.appendingPathComponent(source.lastPathComponent)
            case .renamed(let url): target = url
            }

            if target.standardizedFileURL == source.standardizedFileURL {
                if mode == .move {
                    // Уже на месте — перемещать некуда.
                    result.completedSources.append(source)
                    continue
                }
                target = FileOperations.uniqueURL(for: target, isDirectory: Self.isDirectory(source))
            } else if Self.isDirectory(source), target.standardizedFileURL.path.hasPrefix(source.standardizedFileURL.path + "/") {
                result.failures.append((source, FileOperationError.copyIntoItself(source.lastPathComponent)))
                continue
            }

            let done: Bool
            switch mode {
            case .copy:
                done = copyItem(source, to: target)
            case .move where renameSources.contains(source):
                done = moveItem(source, to: target)
                progress.copiedFiles += 1
                reportProgress(force: false)
            case .move:
                done = copyThenDelete(source, to: target)
            }
            if done {
                result.completedSources.append(source)
            }
        }
        result.cancelled = cancellation.isCancelled
    }

    /// Перемещение на другой том: копия, затем удаление источника (только если скопирован целиком).
    private func copyThenDelete(_ source: URL, to target: URL) -> Bool {
        guard copyItem(source, to: target) else { return false }
        do {
            try FileManager.default.removeItem(at: source)
            return true
        } catch {
            result.failures.append((source, error))
            return false
        }
    }

    /// Перемещение в пределах тома переименованием. Папка в существующую папку — слияние содержимого.
    private func moveItem(_ source: URL, to target: URL) -> Bool {
        if cancellation.isCancelled { return false }
        var target = target

        if Self.exists(target) {
            if Self.isDirectory(source) && Self.isDirectory(target) {
                let children: [URL]
                do {
                    children = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
                } catch {
                    result.failures.append((source, error))
                    return false
                }
                var complete = true
                for child in children {
                    if cancellation.isCancelled { return false }
                    if !moveItem(child, to: target.appendingPathComponent(child.lastPathComponent)) {
                        complete = false
                    }
                }
                if complete { rmdir(source.path) }
                return complete && !cancellation.isCancelled
            }

            switch choice(for: Conflict(source: source, destination: target)) {
            case .skip:
                return false
            case .cancel:
                cancellation.cancel()
                return false
            case .keepBoth:
                target = FileOperations.uniqueURL(for: target, isDirectory: Self.isDirectory(source))
            case .replace:
                // Файл поверх файла rename(2) заменяет сам и атомарно; при разных типах сначала убираем старое.
                if Self.isDirectory(source) || Self.isDirectory(target) {
                    do { try FileManager.default.removeItem(at: target) } catch {
                        result.failures.append((target, error))
                        return false
                    }
                }
            }
        }

        if rename(source.path, target.path) != 0 {
            let renameError = errno
            if renameError == EXDEV {
                // Оказалось, что это разные тома (например, точка монтирования внутри) — копируем.
                return copyThenDelete(source, to: target)
            }
            result.failures.append((source, POSIXError(POSIXErrorCode(rawValue: renameError) ?? .EIO)))
            return false
        }
        return true
    }

    /// Возвращает `true`, если элемент скопирован целиком (не пропущен, без ошибок, без отмены).
    private func copyItem(_ source: URL, to target: URL) -> Bool {
        if cancellation.isCancelled { return false }
        var target = target
        let sourceIsDirectory = Self.isDirectory(source)
        var replaceExistingFile = false

        if Self.exists(target) {
            if sourceIsDirectory && Self.isDirectory(target) {
                // Папка в папку — сливаем содержимое.
            } else {
                switch choice(for: Conflict(source: source, destination: target)) {
                case .skip:
                    skip(source)
                    return false
                case .cancel:
                    cancellation.cancel()
                    return false
                case .keepBoth:
                    target = FileOperations.uniqueURL(for: target, isDirectory: sourceIsDirectory)
                case .replace:
                    if sourceIsDirectory || Self.isDirectory(target) {
                        do { try FileManager.default.removeItem(at: target) } catch {
                            result.failures.append((target, error))
                            skip(source)
                            return false
                        }
                    } else {
                        replaceExistingFile = true
                    }
                }
            }
        }

        if sourceIsDirectory {
            return copyDirectory(source, to: target)
        }
        return copyFile(source, to: target, replacing: replaceExistingFile)
    }

    private func copyDirectory(_ source: URL, to target: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            // Уже есть (слияние) — продолжаем.
        } catch {
            result.failures.append((source, error))
            skip(source)
            return false
        }

        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        } catch {
            result.failures.append((source, error))
            return false
        }

        var complete = true
        for child in children {
            if cancellation.isCancelled { return false }
            if !copyItem(child, to: target.appendingPathComponent(child.lastPathComponent)) {
                complete = false
            }
        }
        // Атрибуты папки (даты, права) — после содержимого, иначе дата изменения собьётся.
        copyfile(source.path, target.path, nil, copyfile_flags_t(COPYFILE_METADATA))
        return complete && !cancellation.isCancelled
    }

    private func copyFile(_ source: URL, to target: URL, replacing: Bool) -> Bool {
        progress.currentName = source.lastPathComponent
        bytesBeforeCurrentFile = progress.copiedBytes
        reportProgress(force: true)

        let writeURL = replacing
            ? target.deletingLastPathComponent().appendingPathComponent(".mtc-\(UUID().uuidString)-\(target.lastPathComponent)")
            : target

        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let callback: copyfile_callback_t = { what, stage, state, _, _, context in
            guard let context else { return Int32(COPYFILE_CONTINUE) }
            let operation = Unmanaged<CopyOperation>.fromOpaque(context).takeUnretainedValue()
            if what == Int32(COPYFILE_COPY_DATA), stage == Int32(COPYFILE_PROGRESS) {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                operation.fileProgress(Int64(copied))
            }
            return operation.cancellation.isCancelled ? Int32(COPYFILE_QUIT) : Int32(COPYFILE_CONTINUE)
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(self).toOpaque())

        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC | COPYFILE_CLONE)
        let status = copyfile(source.path, writeURL.path, state, flags)
        let copyError = errno

        // При отмене засчитываем только реально скопированное, иначе — файл целиком (в т.ч. при ошибке, чтобы полоса шла дальше).
        if !cancellation.isCancelled {
            progress.copiedBytes = bytesBeforeCurrentFile + Self.fileSize(source)
        }

        if status != 0 {
            try? FileManager.default.removeItem(at: writeURL)
            if !cancellation.isCancelled {
                result.failures.append((source, POSIXError(POSIXErrorCode(rawValue: copyError) ?? .EIO)))
            }
            return false
        }

        // rename(2) атомарно подменяет файл или ссылку и не ходит по символическим ссылкам.
        if replacing, rename(writeURL.path, target.path) != 0 {
            let renameError = errno
            try? FileManager.default.removeItem(at: writeURL)
            result.failures.append((source, POSIXError(POSIXErrorCode(rawValue: renameError) ?? .EIO)))
            return false
        }

        progress.copiedFiles += 1
        reportProgress(force: false)
        return true
    }

    // MARK: - Конфликты

    private func choice(for conflict: Conflict) -> ConflictChoice {
        if let rememberedChoice { return rememberedChoice }
        guard let resolveConflict else { return .skip }

        let semaphore = DispatchSemaphore(value: 0)
        var answer: (ConflictChoice, Bool) = (.cancel, false)
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

    // MARK: - Прогресс

    private func scan() {
        for source in sources {
            if cancellation.isCancelled { return }
            if renameSources.contains(source) {
                // Переименование мгновенное — считаем как один объект.
                progress.totalFiles += 1
            } else if Self.isDirectory(source) {
                let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
                let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
                while let url = enumerator?.nextObject() as? URL {
                    if cancellation.isCancelled { return }
                    guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                    progress.totalFiles += 1
                    progress.totalBytes += Int64(values.fileSize ?? 0)
                    reportProgress(force: false)
                }
            } else {
                progress.totalFiles += 1
                progress.totalBytes += Self.fileSize(source)
            }
        }
    }

    /// Пропущенное считаем «сделанным», чтобы полоса прогресса дошла до конца.
    private func skip(_ source: URL) {
        if Self.isDirectory(source) {
            let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            while let url = enumerator?.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
                progress.copiedFiles += 1
                progress.copiedBytes += Int64(values.fileSize ?? 0)
            }
        } else {
            progress.copiedFiles += 1
            progress.copiedBytes += Self.fileSize(source)
        }
        reportProgress(force: false)
    }

    private func fileProgress(_ copied: Int64) {
        progress.copiedBytes = bytesBeforeCurrentFile + copied
        reportProgress(force: false)
    }

    private func reportProgress(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastProgressReport) > 0.1 else { return }
        lastProgressReport = now
        let snapshot = progress
        DispatchQueue.main.async { [weak self] in self?.onProgress?(snapshot) }
    }

    // MARK: - Файловая система

    /// Папка (символическая ссылка на папку папкой не считается — копируется как ссылка).
    private static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        guard let first = (try? a.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier,
              let second = (try? b.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier else { return false }
        return first.isEqual(second)
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func fileSize(_ url: URL) -> Int64 {
        var info = stat()
        return lstat(url.path, &info) == 0 ? Int64(info.st_size) : 0
    }
}
