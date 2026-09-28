import Foundation

enum SortKey: String {
    case name, ext, size, modified
}

enum DirectoryLister {
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey,
        .fileSizeKey, .contentModificationDateKey,
    ]

    static func list(_ directory: URL, showHidden: Bool) throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: showHidden ? [] : [.skipsHiddenFiles]
        )
        return urls.map(makeItem)
    }

    static func sorted(_ items: [FileItem], by key: SortKey, ascending: Bool) -> [FileItem] {
        items.sorted { a, b in
            // Папки всегда выше файлов.
            if a.isContainer != b.isContainer { return a.isContainer }

            let result: ComparisonResult
            switch key {
            case .name:
                result = a.name.localizedStandardCompare(b.name)
            case .ext:
                result = a.ext.localizedStandardCompare(b.ext)
            case .size:
                result = compare(a.size ?? -1, b.size ?? -1)
            case .modified:
                result = compare(a.modified ?? .distantPast, b.modified ?? .distantPast)
            }

            if result == .orderedSame {
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private static func makeItem(_ url: URL) -> FileItem {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        let isSymlink = values?.isSymbolicLink ?? false

        var isDirectory = values?.isDirectory ?? false
        var isPackage = values?.isPackage ?? false
        if isSymlink, let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) {
            isDirectory = target.isDirectory ?? false
            isPackage = target.isPackage ?? false
        }

        let kind: FileItem.Kind = isDirectory ? (isPackage ? .package : .directory) : .file
        return FileItem(
            url: url,
            kind: kind,
            name: url.lastPathComponent,
            size: kind == .file ? values?.fileSize.map(Int64.init) : nil,
            modified: values?.contentModificationDate,
            isHidden: values?.isHidden ?? false,
            isSymlink: isSymlink
        )
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
