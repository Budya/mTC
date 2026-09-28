import AppKit
import UniformTypeIdentifiers

enum FileOperationError: LocalizedError {
    case emptyName
    case invalidName(String)
    case copyIntoItself(String)
    case alreadyExists(String)
    case unsafeArchiveEntries(Int)

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Имя не может быть пустым."
        case .invalidName(let name): return "Недопустимое имя «\(name)»."
        case .copyIntoItself(let name): return "Нельзя поместить папку «\(name)» внутрь неё самой."
        case .alreadyExists(let name): return "«\(name)» уже существует."
        case .unsafeArchiveEntries(let count): return "Пропущено элементов с небезопасным путём (.. или ссылка наружу): \(count)."
        }
    }
}

enum FileOperations {
    /// Свободное имя рядом с `url`: если занято — добавляет номер, как Finder.
    /// Папки: «Новая папка 2», «v1.2 2». Файлы: номер перед расширением — «отчёт 2.txt».
    static func uniqueURL(for url: URL, isDirectory: Bool = true) -> URL {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return url }
        let parent = url.deletingLastPathComponent()
        let ext = isDirectory ? "" : url.pathExtension
        let stem = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = parent.appendingPathComponent(name, isDirectory: isDirectory)
            if lstat(candidate.path, &info) != 0 { return candidate }
            index += 1
        }
    }

    /// Создаёт папку в `parent`. Как в Total Commander, можно сразу создать вложенные: `папка/подпапка`,
    /// или указать абсолютный путь (`/…`, `~/…`). Если папка уже есть — к последнему имени добавляется номер.
    /// Возвращает папку внутри `parent`, на которую ставится курсор (для абсолютного пути — саму созданную).
    @discardableResult
    static func createDirectory(named input: String, in parent: URL) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FileOperationError.emptyName }

        let isAbsolute = trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
        let base = isAbsolute ? URL(fileURLWithPath: "/") : parent
        let path = isAbsolute ? (trimmed as NSString).expandingTildeInPath : trimmed

        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw FileOperationError.invalidName(trimmed)
        }

        let target = uniqueURL(for: components.reduce(base) { $0.appendingPathComponent($1, isDirectory: true) })
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        if isAbsolute || components.count == 1 { return target }
        return parent.appendingPathComponent(components[0], isDirectory: true)
    }
}

// MARK: - Новый файл

extension FileOperations {
    /// Создаёт пустой файл (можно с подпапками: `папка/файл.txt`). Если файл уже есть — ничего не делает
    /// (как в Total Commander: ⇧F4 по существующему имени просто открывает его). Возвращает путь к файлу.
    @discardableResult
    static func createFile(named input: String, in parent: URL) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FileOperationError.emptyName }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : parent.appendingPathComponent(expanded)
        let components = expanded.split(separator: "/")
        guard !components.isEmpty, !components.contains(where: { $0 == "." || $0 == ".." }), !trimmed.hasSuffix("/") else {
            throw FileOperationError.invalidName(trimmed)
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { throw FileOperationError.alreadyExists(trimmed) }
            return url
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url
    }

    /// Программа-редактор из настройки `editor`: пусто — системный редактор текста;
    /// путь к .app, bundle id (`com.microsoft.VSCode`) или имя (`Visual Studio Code`).
    static func editorApplication(_ setting: String) -> URL? {
        let value = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = NSWorkspace.shared
        if value.isEmpty {
            return workspace.urlForApplication(toOpen: .plainText)
        }
        if value.hasPrefix("/") || value.hasPrefix("~") {
            let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let url = workspace.urlForApplication(withBundleIdentifier: value) {
            return url
        }
        let name = value.hasSuffix(".app") ? value : value + ".app"
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        return folders.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

// MARK: - Переименование

extension FileOperations {
    /// Переименовывает на месте. Разрешает смену только регистра («a.txt» → «A.txt»);
    /// если имя занято другим файлом — ошибка (номер не подставляется).
    static func rename(_ url: URL, to newName: String) throws {
        guard !newName.isEmpty else { throw FileOperationError.emptyName }
        guard !newName.contains("/"), newName != ".", newName != ".." else { throw FileOperationError.invalidName(newName) }

        let target = url.deletingLastPathComponent().appendingPathComponent(newName)
        var info = stat()
        if lstat(target.path, &info) == 0 {
            // На томе без учёта регистра «A.txt» — это тот же файл, что «a.txt».
            let sourceID = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
            let targetID = (try? target.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
            let sameFile = sourceID != nil && targetID != nil && sourceID!.isEqual(targetID!)
            if !sameFile { throw FileOperationError.alreadyExists(newName) }
        }
        if Darwin.rename(url.path, target.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

// MARK: - Копирование

extension FileOperations {
    /// Разбирает путь назначения из диалога F5 (как в Total Commander):
    /// существующая папка или путь с «/» в конце — копируем внутрь; один источник и новый путь — копируем под новым именем;
    /// несколько источников и новый путь — такая папка будет создана. Относительный путь — от папки источника.
    static func copyDestination(for input: String, sourceCount: Int, relativeTo base: URL) -> CopyOperation.Destination? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded)).standardizedFileURL

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if trimmed.hasSuffix("/") || (exists && isDirectory.boolValue) || sourceCount > 1 {
            return .into(url)
        }
        return .renamed(url)
    }
}

// MARK: - Удаление

struct DeletionResult {
    /// Не удалось удалить (или переместить в Корзину) — с причиной.
    var failures: [(url: URL, error: Error)] = []
    /// На томе нет Корзины (например, сетевой диск) — можно предложить удалить насовсем.
    var trashUnavailable: [URL] = []
}

extension FileOperations {
    /// Перемещает в Корзину. Выполнять не на главном потоке.
    static func moveToTrash(_ urls: [URL]) -> DeletionResult {
        var result = DeletionResult()
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch let error as CocoaError where error.code == .featureUnsupported {
                result.trashUnavailable.append(url)
            } catch {
                result.failures.append((url, error))
            }
        }
        return result
    }

    /// Удаляет насовсем. Выполнять не на главном потоке.
    static func deletePermanently(_ urls: [URL]) -> DeletionResult {
        var result = DeletionResult()
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                result.failures.append((url, error))
            }
        }
        return result
    }
}
