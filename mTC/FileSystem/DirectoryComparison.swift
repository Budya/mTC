import Foundation

/// Быстрое сравнение двух папок (только их содержимое, без вложенных), как «Сравнить каталоги» в TC.
///
/// Отмечается то, что стоит скопировать на другую сторону:
/// - есть только с одной стороны (файл или папка) — отмечается там, где есть;
/// - файл есть с обеих сторон, но время изменения разное — отмечается более новый;
/// - время одинаковое, а размер разный — отмечаются оба (непонятно, какой правильный);
/// - файл с одной стороны и папка с таким же именем с другой — отмечаются оба.
/// Одинаковые файлы и папки, которые есть с обеих сторон, не отмечаются.
/// Имена сравниваются без учёта регистра и формы Unicode — как их различает APFS по умолчанию.
enum DirectoryComparison {
    struct Result: Equatable {
        var left: Set<String> = []
        var right: Set<String> = []
        var identical: Bool { left.isEmpty && right.isEmpty }
    }

    /// Разница во времени меньше этой считается совпадением: FAT и exFAT хранят время с точностью 2 секунды,
    /// а сетевые диски иногда отбрасывают доли секунды.
    static let timeTolerance: TimeInterval = 2

    static func compare(left: [FileItem], right: [FileItem]) -> Result {
        let leftByKey = index(left)
        let rightByKey = index(right)
        var result = Result()

        for (key, item) in leftByKey {
            guard let other = rightByKey[key] else {
                result.left.insert(item.name)
                continue
            }
            switch (isFolder(item), isFolder(other)) {
            case (true, true):
                continue
            case (false, false):
                switch newer(item, other) {
                case .left: result.left.insert(item.name)
                case .right: result.right.insert(other.name)
                case .same:
                    if item.size != other.size {
                        result.left.insert(item.name)
                        result.right.insert(other.name)
                    }
                }
            default:
                result.left.insert(item.name)
                result.right.insert(other.name)
            }
        }
        for (key, item) in rightByKey where leftByKey[key] == nil {
            result.right.insert(item.name)
        }
        return result
    }

    private enum Side { case left, right, same }

    private static func newer(_ left: FileItem, _ right: FileItem) -> Side {
        guard let a = left.modified, let b = right.modified else { return .same }
        if abs(a.timeIntervalSince(b)) < timeTolerance { return .same }
        return a > b ? .left : .right
    }

    private static func isFolder(_ item: FileItem) -> Bool {
        item.kind == .directory
    }

    private static func index(_ items: [FileItem]) -> [String: FileItem] {
        var result: [String: FileItem] = [:]
        for item in items where item.kind != .parent {
            result[item.name.precomposedStringWithCanonicalMapping.lowercased()] = item
        }
        return result
    }
}
