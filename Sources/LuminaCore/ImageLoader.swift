import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Lädt Bilder von der Platte, skaliert sie beim Dekodieren herunter und hält sie im Cache.
///
/// Ohne Downsampling würde ein 60-Megapixel-RAW als 240-MB-Bitmap im Speicher landen.
/// `CGImageSourceCreateThumbnailAtIndex` dekodiert stattdessen direkt in der Zielgrösse.
public actor ImageLoader {
    /// NSCache braucht Klassen-Typen, CGImage ist ein CF-Typ - darum dieser Wrapper.
    private final class CachedImage: NSObject {
        let image: CGImage
        let pixelSize: Int
        init(image: CGImage, pixelSize: Int) {
            self.image = image
            self.pixelSize = pixelSize
        }
    }

    private let cache = NSCache<NSString, CachedImage>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    /// - Parameter memoryLimitMB: Obergrenze für den Bild-Cache.
    public init(memoryLimitMB: Int = 512) {
        cache.totalCostLimit = memoryLimitMB * 1024 * 1024
    }

    /// Liefert das Bild in mindestens `maxPixelSize` Kantenlänge.
    ///
    /// Läuft für dieselbe URL nur einmal gleichzeitig; parallele Anfragen (Anzeige +
    /// Vorausladen) teilen sich denselben Task.
    public func image(for url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = url.path as NSString

        if let cached = cache.object(forKey: key), cached.pixelSize >= maxPixelSize {
            return cached.image
        }
        if let running = inFlight[url.path] {
            return await running.value
        }

        let task = Task.detached(priority: .userInitiated) { () -> CGImage? in
            Self.decode(url: url, maxPixelSize: maxPixelSize)
        }
        inFlight[url.path] = task
        let result = await task.value
        inFlight[url.path] = nil

        if let result {
            let cost = result.bytesPerRow * result.height
            cache.setObject(CachedImage(image: result, pixelSize: maxPixelSize), forKey: key, cost: cost)
        }
        return result
    }

    /// Lädt Bilder im Hintergrund vor, ohne auf das Ergebnis zu warten.
    public func prefetch(_ urls: [URL], maxPixelSize: Int) {
        for url in urls where cache.object(forKey: url.path as NSString) == nil && inFlight[url.path] == nil {
            let task = Task.detached(priority: .utility) { () -> CGImage? in
                Self.decode(url: url, maxPixelSize: maxPixelSize)
            }
            inFlight[url.path] = task
            Task { [weak self] in
                let result = await task.value
                await self?.finishPrefetch(url: url, image: result, maxPixelSize: maxPixelSize)
            }
        }
    }

    private func finishPrefetch(url: URL, image: CGImage?, maxPixelSize: Int) {
        inFlight[url.path] = nil
        guard let image else { return }
        let cost = image.bytesPerRow * image.height
        cache.setObject(CachedImage(image: image, pixelSize: maxPixelSize), forKey: url.path as NSString, cost: cost)
    }

    public func clearCache() {
        cache.removeAllObjects()
    }

    /// Dekodiert eine Bilddatei direkt in Zielgrösse und richtet sie nach EXIF-Orientierung aus.
    nonisolated static func decode(url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Liest nur die Bildabmessungen, ohne die Pixel zu dekodieren.
    public nonisolated static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Double,
              let height = props[kCGImagePropertyPixelHeight] as? Double
        else { return nil }

        // Bei 90/270-Grad-Orientierung sind Breite und Höhe vertauscht.
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = orientation >= 5 && orientation <= 8
        return rotated ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
