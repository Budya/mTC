import Foundation

/// Что искать (запоминается в `state.json`).
struct SearchQuery: Codable, Equatable {
    /// Маски имени через `;`: `*.pdf; отчёт`. Без `*` и `?` ищется часть имени. Пусто — любое имя.
    var name = ""
    /// Текст внутри файла (UTF-8). Пусто — содержимое не проверяется.
    var text = ""
    var caseSensitive = false
    var includeHidden = false
    /// Фильтр по дате: какую дату смотреть и за какой период.
    var dateField = SearchDateField.modified
    var datePeriod = SearchDatePeriod.any
    /// Границы для `.interval` (включительно, по дням).
    var dateFrom = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    var dateTo = Date()

    /// Допустимые даты на момент `now`; `nil` — дата не важна.
    func dateRange(now: Date = Date()) -> ClosedRange<Date>? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start: Date?
        switch datePeriod {
        case .any: return nil
        case .today: start = today
        case .week: start = calendar.date(byAdding: .day, value: -7, to: now)
        case .month: start = calendar.date(byAdding: .month, value: -1, to: now)
        case .year: start = calendar.date(byAdding: .year, value: -1, to: now)
        case .interval:
            let from = calendar.startOfDay(for: min(dateFrom, dateTo))
            let toDay = calendar.startOfDay(for: max(dateFrom, dateTo))
            let to = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: toDay) ?? toDay
            return from...to
        }
        return (start ?? now)...Date.distantFuture
    }
}

enum SearchDateField: String, Codable, CaseIterable {
    case modified, created

    var title: String {
        switch self {
        case .modified: return "Изменён"
        case .created: return "Создан"
        }
    }
}

enum SearchDatePeriod: String, Codable, CaseIterable {
    case any, today, week, month, year, interval

    var title: String {
        switch self {
        case .any: return "когда угодно"
        case .today: return "сегодня"
        case .week: return "за 7 дней"
        case .month: return "за месяц"
        case .year: return "за год"
        case .interval: return "с … по …"
        }
    }
}

/// Найденный файл или папка.
struct SearchHit {
    let url: URL
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?
    let created: Date?
    let isHidden: Bool
}

/// Совпадение имени с масками поиска. В отличие от `FileMask` пробел — часть имени,
/// а маска без `*` и `?` означает «имя содержит».
struct SearchNameMatcher {
    private let patterns: [Glob]

    init(_ text: String) {
        patterns = text
            .split(whereSeparator: { $0 == ";" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Glob($0 == "*.*" ? "*" : ($0.contains("*") || $0.contains("?") ? $0 : "*\($0)*")) }
    }

    func matches(_ name: String) -> Bool {
        guard !patterns.isEmpty else { return true }
        let name = Glob.normalized(name)
        return patterns.contains { $0.matches(normalized: name) }
    }
}

/// Поиск в фоне: обходит `root` вглубь (не заходит внутрь пакетов вроде `.app`, по ссылкам
/// и в `/System/Volumes`, `/Volumes`, `/dev` — чтобы поиск от `/` не ходил по одному диску дважды
/// и по всем подключённым), результаты отдаёт пачками. Колбэки — на главном потоке.
final class FileSearchOperation: @unchecked Sendable {
    struct Progress {
        var scannedDirectories = 0
        var currentDirectory = ""
    }

    let root: URL
    let query: SearchQuery

    var onHits: (([SearchHit]) -> Void)?
    var onProgress: ((Progress) -> Void)?
    var onFinish: ((_ cancelled: Bool) -> Void)?

    private let cancellation = CancellationFlag()
    private var pending: [SearchHit] = []
    private var progress = Progress()
    private var lastReport = Date.distantPast

    private static let skippedDirectories: Set<String> = ["/System/Volumes", "/Volumes", "/dev"]

    init(root: URL, query: SearchQuery) {
        self.root = root
        self.query = query
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            run()
            flush(force: true)
            let cancelled = cancellation.isCancelled
            DispatchQueue.main.async { self.onFinish?(cancelled) }
        }
    }

    func cancel() {
        cancellation.cancel()
    }

    private func run() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .isHiddenKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !query.includeHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: options, errorHandler: { _, _ in true }) else { return }

        let names = SearchNameMatcher(query.name)
        let needle = query.text.isEmpty ? nil : ContentMatcher(query.text, caseSensitive: query.caseSensitive)
        let dates = query.dateRange()

        for case let url as URL in enumerator {
            if cancellation.isCancelled { return }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isDirectory = values.isDirectory == true && values.isPackage != true

            if isDirectory {
                if Self.skippedDirectories.contains(url.path) {
                    enumerator.skipDescendants()
                    continue
                }
                progress.scannedDirectories += 1
                progress.currentDirectory = url.path
            }

            guard names.matches(url.lastPathComponent) else { continue }
            if let dates {
                let date = query.dateField == .created ? values.creationDate : values.contentModificationDate
                guard let date, dates.contains(date) else { continue }
            }
            if let needle {
                // Текст ищем только в обычных файлах.
                guard values.isRegularFile == true, needle.matches(fileAt: url, cancellation: cancellation) else { continue }
            }
            pending.append(SearchHit(
                url: url,
                isDirectory: isDirectory,
                size: isDirectory ? nil : values.fileSize.map(Int64.init),
                modified: values.contentModificationDate,
                created: values.creationDate,
                isHidden: values.isHidden == true
            ))
            flush(force: false)
        }
    }

    /// Не чаще 5 раз в секунду: иначе таблица результатов не успевает.
    private func flush(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) > 0.2 else { return }
        lastReport = now
        let hits = pending
        let progress = progress
        pending.removeAll()
        DispatchQueue.main.async {
            if !hits.isEmpty { self.onHits?(hits) }
            self.onProgress?(progress)
        }
    }
}

/// Поиск текста в файле кусками по 1 МБ с перекрытием, чтобы не пропустить совпадение на стыке.
/// Без учёта регистра кусок читается как UTF-8 (битые байты заменяются) и сравнивается строкой.
private struct ContentMatcher {
    let text: String
    let bytes: Data
    let caseSensitive: Bool

    init(_ text: String, caseSensitive: Bool) {
        self.text = text
        self.caseSensitive = caseSensitive
        bytes = Data(text.utf8)
    }

    func matches(fileAt url: URL, cancellation: CancellationFlag) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let overlap = bytes.count * 2 + 4
        var tail = Data()
        while !cancellation.isCancelled {
            guard let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty else { return false }
            let window = tail + chunk
            if caseSensitive {
                if window.range(of: bytes) != nil { return true }
            } else if String(decoding: window, as: UTF8.self).range(of: text, options: .caseInsensitive) != nil {
                return true
            }
            tail = window.suffix(overlap)
        }
        return false
    }
}
