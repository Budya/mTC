import Foundation

/// JSON-файл с настройками.
///
/// - Читаемый формат: отступы и отсортированные ключи, файл удобно править руками.
/// - Недостающие ключи берутся из значений по умолчанию, поэтому новые поля
///   не ломают старые файлы.
/// - Повреждённый файл переименовывается в `*.broken-<время>.json`, дальше работаем с умолчаниями.
/// - Запись атомарная (временный файл и замена) и отложенная, чтобы частые изменения
///   (размер окна, текущие пути) не писались на диск на каждое событие.
/// - `fileURL == nil` означает режим без сохранения.
final class JSONStore<Value: Codable> {
    private(set) var value: Value
    let fileURL: URL?

    private let saveDelay: TimeInterval
    private var pendingSave: DispatchWorkItem?
    private var lastWrittenData: Data?

    init(fileURL: URL?, defaultValue: Value, saveDelay: TimeInterval = 1.0) {
        self.fileURL = fileURL
        self.saveDelay = saveDelay
        self.value = defaultValue

        guard let fileURL else { return }
        if let data = try? Data(contentsOf: fileURL) {
            if let loaded = Self.decode(data, defaults: defaultValue) {
                value = loaded
                lastWrittenData = data
            } else {
                Self.moveAsideBroken(fileURL)
            }
        }
        // Создаём файл при первом запуске и дописываем в него новые ключи.
        write()
    }

    func update(_ change: (inout Value) -> Void) {
        change(&value)
        scheduleSave()
    }

    /// Немедленно записывает отложенные изменения (вызывается при выходе).
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        write()
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.write()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    private func write() {
        guard let fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            guard data != lastWrittenData else { return }
            try data.write(to: fileURL, options: .atomic)
            lastWrittenData = data
        } catch {
            NSLog("mTC: не удалось сохранить \(fileURL.lastPathComponent): \(error)")
        }
    }

    private static func decode(_ data: Data, defaults: Value) -> Value? {
        do {
            let loaded = try JSONSerialization.jsonObject(with: data)
            let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))
            let merged = deepMerge(base, loaded)
            let mergedData = try JSONSerialization.data(withJSONObject: merged)
            return try JSONDecoder().decode(Value.self, from: mergedData)
        } catch {
            NSLog("mTC: не удалось прочитать настройки: \(error)")
            return nil
        }
    }

    private static func deepMerge(_ base: Any, _ override: Any) -> Any {
        guard var baseDict = base as? [String: Any], let overrideDict = override as? [String: Any] else {
            return override
        }
        for (key, value) in overrideDict {
            baseDict[key] = baseDict[key].map { deepMerge($0, value) } ?? value
        }
        return baseDict
    }

    private static func moveAsideBroken(_ url: URL) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = url.deletingPathExtension().lastPathComponent
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(name).broken-\(formatter.string(from: Date())).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}
