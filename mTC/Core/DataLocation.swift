import Foundation

/// Где лежат настройки: папка `mTC-data` рядом с `mTC.app`.
///
/// Порядок выбора:
/// 1. аргумент `--data-dir <путь>` или переменная окружения `MTC_DATA_DIR`
///    (так работает запуск из Xcode — см. схему mTC);
/// 2. `mTC-data` рядом с `mTC.app`.
///
/// В `~/Library` ничего не пишем: если папка недоступна, приложение работает без сохранения.
struct DataLocation {
    enum Problem: Equatable {
        /// macOS запустил приложение из временной read-only копии (карантин).
        case translocated(originalAppURL: URL?)
        /// Папку нельзя создать или в неё нельзя писать.
        case notWritable
        /// Эту папку уже использует другой запущенный экземпляр.
        case lockedByAnotherInstance
    }

    static let folderName = "mTC-data"
    static let environmentKey = "MTC_DATA_DIR"
    static let argumentKey = "--data-dir"

    let directory: URL
    var problem: Problem?

    var canPersist: Bool { problem == nil }

    func file(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func resolve(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL
    ) -> DataLocation {
        if let override = overridePath(arguments: arguments, environment: environment) {
            let path = (override as NSString).expandingTildeInPath
            return prepared(URL(fileURLWithPath: path).standardizedFileURL)
        }

        let directory = bundleURL.deletingLastPathComponent().appendingPathComponent(folderName)
        if Translocation.isTranslocated(bundleURL) {
            let original = Translocation.originalURL(for: bundleURL)
            return DataLocation(directory: directory, problem: .translocated(originalAppURL: original))
        }
        return prepared(directory)
    }

    private static func overridePath(arguments: [String], environment: [String: String]) -> String? {
        if let index = arguments.firstIndex(of: argumentKey), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        if let value = environment[environmentKey], !value.isEmpty {
            return value
        }
        return nil
    }

    private static func prepared(_ directory: URL) -> DataLocation {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return DataLocation(directory: directory, problem: .notWritable)
        }
        guard fm.isWritableFile(atPath: directory.path) else {
            return DataLocation(directory: directory, problem: .notWritable)
        }
        return DataLocation(directory: directory, problem: nil)
    }
}

/// App Translocation: приложение с атрибутом карантина macOS запускает из случайного
/// read-only пути, поэтому соседнюю папку `mTC-data` оттуда не видно.
enum Translocation {
    static func isTranslocated(_ url: URL) -> Bool {
        url.path.contains("/AppTranslocation/")
    }

    /// Исходный путь до `.app` (через SecTranslocateCreateOriginalPathForURL, если доступна).
    static func originalURL(for url: URL) -> URL? {
        typealias CreateOriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }

        let createOriginalPath = unsafeBitCast(symbol, to: CreateOriginalPath.self)
        return createOriginalPath(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}
