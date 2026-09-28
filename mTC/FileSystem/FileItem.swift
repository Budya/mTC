import Foundation

struct FileItem {
    enum Kind {
        /// Строка «..» для перехода наверх.
        case parent
        case directory
        /// Бандл, который Finder показывает как файл (`.app`, `.bundle` и т.п.).
        case package
        case file
    }

    let url: URL
    let kind: Kind
    let name: String
    let size: Int64?
    let modified: Date?
    let isHidden: Bool
    let isSymlink: Bool

    var isContainer: Bool { kind == .parent || kind == .directory }

    /// Имя без расширения — как в Total Commander, где расширение идёт отдельной колонкой.
    var displayName: String {
        switch kind {
        case .parent: return ".."
        case .directory: return name
        case .package, .file: return ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        }
    }

    var ext: String {
        switch kind {
        case .parent, .directory: return ""
        case .package, .file: return url.pathExtension
        }
    }

    static func parent(of directory: URL) -> FileItem {
        FileItem(
            url: directory.deletingLastPathComponent(),
            kind: .parent,
            name: "..",
            size: nil,
            modified: nil,
            isHidden: false,
            isSymlink: false
        )
    }
}
