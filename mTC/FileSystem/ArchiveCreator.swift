import Foundation

/// Формат создаваемого архива.
enum ArchiveKind: String, CaseIterable, Codable {
    case zip, sevenZip = "7z", tarGz = "tar.gz", tarXz = "tar.xz"

    var title: String {
        switch self {
        case .zip: return "ZIP"
        case .sevenZip: return "7Z"
        case .tarGz: return "TAR.GZ"
        case .tarXz: return "TAR.XZ"
        }
    }

    var fileExtension: String { rawValue }

    /// Пароль libarchive умеет ставить только на zip.
    var supportsPassword: Bool { self == .zip }

    /// «имя.tar.gz» → «имя» (любое из наших расширений).
    static func stripExtension(_ name: String) -> String {
        for kind in allCases.sorted(by: { $0.rawValue.count > $1.rawValue.count }) {
            let suffix = "." + kind.fileExtension
            if name.lowercased().hasSuffix(suffix), name.count > suffix.count {
                return String(name.dropLast(suffix.count))
            }
        }
        return name
    }
}

/// Шифрование zip с паролем.
enum ZipEncryption: String, CaseIterable, Codable {
    /// Классическое шифрование zip: открывается двойным щелчком в Finder и где угодно, но защита слабая.
    case zipCrypto
    /// AES-256: надёжно, но Finder такой архив не откроет — нужен mTC, 7-Zip или Keka.
    case aes256

    var title: String {
        switch self {
        case .zipCrypto: return "Совместимое (ZipCrypto)"
        case .aes256: return "Надёжное (AES-256)"
        }
    }

    var libarchiveOption: String {
        switch self {
        case .zipCrypto: return "zip:encryption=zipcrypt"
        case .aes256: return "zip:encryption=aes256"
        }
    }
}

/// Создание архива через системную libarchive.
///
/// Пишет во временный файл рядом и только в конце переименовывает в итоговое имя —
/// при отмене или ошибке недописанного архива не остаётся. `.DS_Store` не кладутся.
/// Имена приводятся к составной форме Unicode (NFC), чтобы архив правильно читался на Windows.
/// Шифрование zip — `ZipEncryption`.
///
/// Колбэки вызываются на главном потоке.
final class ArchiveCreateOperation: @unchecked Sendable {
    struct Result {
        var archive: URL?
        var failures: [(url: URL, error: Error)] = []
        var cancelled = false
    }

    let sources: [URL]
    let destination: URL
    let kind: ArchiveKind
    let password: String?
    let encryption: ZipEncryption

    var onProgress: ((CopyOperation.Progress) -> Void)?
    var onFinish: ((Result) -> Void)?

    private let cancellation = CancellationFlag()
    private var progress = CopyOperation.Progress()
    private var result = Result()
    private var lastReport = Date.distantPast

    init(sources: [URL], destination: URL, kind: ArchiveKind, password: String?, encryption: ZipEncryption = .zipCrypto) {
        self.sources = sources
        self.encryption = encryption
        self.destination = destination
        self.kind = kind
        self.password = password?.isEmpty == true ? nil : password
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

    private func run() {
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".mtc-pack-\(UUID().uuidString).\(kind.fileExtension)")
        let items = collectItems(excluding: temp)
        progress.isScanning = false
        report(force: true)
        if cancellation.isCancelled { result.cancelled = true; return }

        guard let archive = archive_write_new() else { return }
        var opened = false
        defer {
            if opened { archive_write_close(archive) }
            archive_write_free(archive)
            try? FileManager.default.removeItem(at: temp)
        }

        switch kind {
        case .zip: archive_write_set_format_zip(archive)
        case .sevenZip: archive_write_set_format_7zip(archive)
        case .tarGz:
            archive_write_set_format_pax_restricted(archive)
            archive_write_add_filter_gzip(archive)
        case .tarXz:
            archive_write_set_format_pax_restricted(archive)
            archive_write_add_filter_xz(archive)
        }
        if kind == .zip, let password {
            archive_write_set_options(archive, encryption.libarchiveOption)
            archive_write_set_passphrase(archive, password)
        }

        guard archive_write_open_filename(archive, temp.path) == ARCHIVE_OK else {
            result.failures.append((destination, Self.error(archive, fallback: "Не удалось создать архив")))
            return
        }
        opened = true

        for item in items {
            if cancellation.isCancelled { break }
            if !write(item, to: archive) { break }
        }
        if cancellation.isCancelled {
            result.cancelled = true
            return
        }

        // close дописывает оглавление — ошибки здесь тоже важны.
        opened = false
        guard archive_write_close(archive) == ARCHIVE_OK else {
            result.failures.append((destination, Self.error(archive, fallback: "Не удалось дописать архив")))
            return
        }
        if Darwin.rename(temp.path, destination.path) != 0 {
            result.failures.append((destination, POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)))
            return
        }
        result.archive = destination
    }

    // MARK: - Что кладём

    private struct Item {
        let url: URL
        /// Путь внутри архива.
        let path: String
        let type: mode_t
        let size: Int64
        let permissions: mode_t
        let modified: time_t
        let linkTarget: String?
    }

    /// Все файлы и папки источников (без захода по ссылкам), пути — от папки, где лежат источники.
    private func collectItems(excluding skipped: URL) -> [Item] {
        var items: [Item] = []
        for source in sources {
            let base = source.deletingLastPathComponent().path
            var queue = [source]
            while let url = queue.popLast() {
                if cancellation.isCancelled { return items }
                guard url.path != skipped.path, url.lastPathComponent != ".DS_Store" else { continue }
                var info = stat()
                guard lstat(url.path, &info) == 0 else { continue }

                let relative = String(url.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let type = info.st_mode & S_IFMT
                let link = type == S_IFLNK ? try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil
                items.append(Item(
                    url: url,
                    path: relative.precomposedStringWithCanonicalMapping,
                    type: type,
                    size: type == S_IFREG ? Int64(info.st_size) : 0,
                    permissions: info.st_mode & 0o7777,
                    modified: info.st_mtimespec.tv_sec,
                    linkTarget: link
                ))
                if type == S_IFREG {
                    progress.totalFiles += 1
                    progress.totalBytes += Int64(info.st_size)
                }
                if type == S_IFDIR {
                    let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                    queue.append(contentsOf: children.sorted { $0.lastPathComponent > $1.lastPathComponent })
                }
                report(force: false)
            }
        }
        return items
    }

    private func write(_ item: Item, to archive: OpaquePointer) -> Bool {
        guard let entry = archive_entry_new() else { return false }
        defer { archive_entry_free(entry) }

        archive_entry_set_pathname_utf8(entry, item.path + (item.type == S_IFDIR ? "/" : ""))
        archive_entry_set_filetype(entry, UInt32(item.type))
        archive_entry_set_perm(entry, item.permissions)
        archive_entry_set_mtime(entry, item.modified, 0)
        archive_entry_set_size(entry, item.size)
        if let linkTarget = item.linkTarget {
            archive_entry_set_symlink_utf8(entry, linkTarget)
        }

        guard archive_write_header(archive, entry) >= ARCHIVE_WARN else {
            result.failures.append((item.url, Self.error(archive, fallback: "Не удалось добавить в архив")))
            return false
        }
        guard item.type == S_IFREG else { return true }

        progress.currentName = item.url.lastPathComponent
        guard let handle = try? FileHandle(forReadingFrom: item.url) else {
            result.failures.append((item.url, CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: item.url.path])))
            return true
        }
        defer { try? handle.close() }

        while !cancellation.isCancelled {
            guard let chunk = try? handle.read(upToCount: 256 * 1024), !chunk.isEmpty else { break }
            let written = chunk.withUnsafeBytes { archive_write_data(archive, $0.baseAddress, chunk.count) }
            guard written >= 0 else {
                result.failures.append((item.url, Self.error(archive, fallback: "Ошибка записи архива")))
                return false
            }
            progress.copiedBytes += Int64(chunk.count)
            report(force: false)
        }
        progress.copiedFiles += 1
        return true
    }

    // MARK: - Вспомогательное

    private func report(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) > 0.1 else { return }
        lastReport = now
        let snapshot = progress
        DispatchQueue.main.async { [weak self] in self?.onProgress?(snapshot) }
    }

    private static func error(_ archive: OpaquePointer, fallback: String) -> Error {
        let message = archive_error_string(archive).map { String(cString: $0) } ?? fallback
        return NSError(domain: "mTC.archive", code: Int(archive_errno(archive)), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
