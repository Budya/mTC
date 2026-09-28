import AppKit
import UniformTypeIdentifiers

/// Иконки для списка файлов. Кешируются по расширению (для бандлов — по пути,
/// потому что у каждого `.app` своя иконка).
enum IconProvider {
    private static var cache: [String: NSImage] = [:]
    private static let iconSize = NSSize(width: 16, height: 16)

    static func icon(for item: FileItem) -> NSImage {
        let key: String
        switch item.kind {
        case .parent: key = "::parent"
        case .directory: key = "::folder"
        case .package: key = "path:" + item.url.path
        case .file: key = "ext:" + item.ext.lowercased()
        }

        if let cached = cache[key] { return cached }

        let image: NSImage
        switch item.kind {
        case .parent:
            image = NSImage(systemSymbolName: "arrowshape.turn.up.left", accessibilityDescription: "..")
                ?? NSWorkspace.shared.icon(for: .folder)
        case .directory:
            image = NSWorkspace.shared.icon(for: .folder)
        case .package:
            image = NSWorkspace.shared.icon(forFile: item.url.path)
        case .file:
            let type = item.ext.isEmpty ? nil : UTType(filenameExtension: item.ext)
            image = NSWorkspace.shared.icon(for: type ?? .data)
        }

        let sized = (image.copy() as? NSImage) ?? image
        sized.size = iconSize
        cache[key] = sized
        return sized
    }
}
