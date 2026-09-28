import AppKit

/// Подключённый том: системный диск, внешний диск, флешка, сетевая шара, образ диска.
struct Volume: Equatable {
    let url: URL
    let name: String
    let isRoot: Bool
    let isEjectable: Bool
    let isLocal: Bool
}

struct VolumeCapacity {
    let available: Int64
    let total: Int64
}

enum Volumes {
    private static let keys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeIsBrowsableKey, .volumeIsEjectableKey,
        .volumeIsLocalKey, .volumeIsRootFileSystemKey,
    ]

    /// Тома, которые видит пользователь (без скрытых системных `/System/Volumes/*`).
    /// Системный диск первым, остальные по имени.
    static func mounted() -> [Volume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let volumes: [Volume] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false else { return nil }
            return Volume(
                url: url.standardizedFileURL,
                name: values.volumeLocalizedName ?? url.lastPathComponent,
                isRoot: values.volumeIsRootFileSystem ?? (url.path == "/"),
                isEjectable: values.volumeIsEjectable ?? false,
                isLocal: values.volumeIsLocal ?? true
            )
        }
        return volumes.sorted { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Корень тома, на котором лежит `url`.
    static func volumeURL(containing url: URL) -> URL? {
        (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume?.standardizedFileURL
    }

    static func capacity(of url: URL) -> VolumeCapacity? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity else { return nil }
        // «Для важных данных» учитывает место, которое macOS может освободить (кеши, снимки) — как Finder.
        let available = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) ?? 0
        return VolumeCapacity(available: available, total: Int64(total))
    }

    static func icon(for volume: Volume) -> NSImage {
        let image = (NSWorkspace.shared.icon(forFile: volume.url.path).copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
