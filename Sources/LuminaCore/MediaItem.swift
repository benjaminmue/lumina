import Foundation
import UniformTypeIdentifiers

/// Ein einzelnes Bild in der Slideshow.
public struct MediaItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let fileSize: Int64

    public init(url: URL, name: String, creationDate: Date?, modificationDate: Date?, fileSize: Int64) {
        self.url = url
        self.name = name
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }

    /// Stabiler Seed für Animationen, die zum Bild gehören.
    public var seed: UInt64 { url.path.stableHash }

    /// Liest die Datei-Metadaten. Gibt `nil` zurück, wenn die URL kein lesbares Bild ist.
    public init?(url: URL) {
        guard MediaScanner.isSupportedImage(url) else { return nil }
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .nameKey]
        let values = try? url.resourceValues(forKeys: keys)
        self.url = url
        self.name = values?.name ?? url.lastPathComponent
        self.creationDate = values?.creationDate
        self.modificationDate = values?.contentModificationDate
        self.fileSize = Int64(values?.fileSize ?? 0)
    }
}

/// Findet Bilddateien auf der Platte und bringt sie in die gewünschte Reihenfolge.
public enum MediaScanner {
    /// Dateiendungen als Fallback, falls das System keinen Content-Type liefert
    /// (etwa bei Netzlaufwerken ohne Metadaten).
    public static let fallbackExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "gif", "heic", "heif", "tiff", "tif",
        "bmp", "webp", "avif", "jp2", "psd", "dng", "cr2", "cr3", "nef",
        "arw", "orf", "raf", "rw2",
    ]

    public static func isSupportedImage(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()),
           type.conforms(to: .image) {
            return true
        }
        return fallbackExtensions.contains(url.pathExtension.lowercased())
    }

    /// Sammelt alle Bilder aus einer Menge von URLs. Ordner werden aufgelöst,
    /// Einzeldateien direkt übernommen. Duplikate fallen raus.
    public static func collect(from urls: [URL], recursive: Bool) -> [MediaItem] {
        var seen = Set<URL>()
        var items: [MediaItem] = []

        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                for fileURL in scanDirectory(url, recursive: recursive) {
                    let standardized = fileURL.standardizedFileURL
                    guard !seen.contains(standardized), let item = MediaItem(url: standardized) else { continue }
                    seen.insert(standardized)
                    items.append(item)
                }
            } else {
                let standardized = url.standardizedFileURL
                guard !seen.contains(standardized), let item = MediaItem(url: standardized) else { continue }
                seen.insert(standardized)
                items.append(item)
            }
        }
        return items
    }

    private static func scanDirectory(_ directory: URL, recursive: Bool) -> [URL] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true, isSupportedImage(url) else { continue }
            result.append(url)
        }
        return result
    }

    /// Sortiert die Bildliste. `shuffled` nutzt einen festen Seed, damit dieselbe
    /// Liste innerhalb einer Session stabil bleibt.
    public static func sort(_ items: [MediaItem], by order: SortOrder, ascending: Bool, seed: UInt64 = 0x5EED) -> [MediaItem] {
        let sorted: [MediaItem]
        switch order {
        case .name:
            sorted = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateCreated:
            sorted = items.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        case .dateModified:
            sorted = items.sorted { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
        case .fileSize:
            sorted = items.sorted { $0.fileSize < $1.fileSize }
        case .shuffled:
            var rng = SeededGenerator(seed: seed)
            // Zufall kennt keine Richtung; `ascending` wird hier bewusst ignoriert.
            return items.shuffled(using: &rng)
        }
        return ascending ? sorted : sorted.reversed()
    }
}
