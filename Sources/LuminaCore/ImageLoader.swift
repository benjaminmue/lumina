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

    /// Wrapper für den Animations-Cache.
    private final class CachedAnimation: NSObject {
        let animation: AnimatedImage
        let pixelSize: Int
        init(animation: AnimatedImage, pixelSize: Int) {
            self.animation = animation
            self.pixelSize = pixelSize
        }
    }

    private let cache = NSCache<NSString, CachedImage>()
    private let animationCache = NSCache<NSString, CachedAnimation>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]
    private let animationBudgetBytes: Int

    /// - Parameters:
    ///   - memoryLimitMB: Obergrenze für den Standbild-Cache.
    ///   - animationBudgetMB: Obergrenze für dekodierte Animationen. Ein Cinemagraph mit
    ///     200 Frames in Full HD wären roh über 1.6 GB - das Budget erzwingt Downsampling.
    public init(memoryLimitMB: Int = 512, animationBudgetMB: Int = 384) {
        cache.totalCostLimit = memoryLimitMB * 1024 * 1024
        animationCache.totalCostLimit = animationBudgetMB * 1024 * 1024
        animationBudgetBytes = animationBudgetMB * 1024 * 1024
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
        animationCache.removeAllObjects()
    }

    // MARK: - Animationen

    /// Lädt alle Frames eines animierten Bildes (WebP, GIF, APNG).
    ///
    /// Gibt `nil` zurück, wenn die Datei nur einen Frame hat - dann ist der normale
    /// Standbild-Weg zuständig.
    public func animation(for url: URL, maxPixelSize: Int) async -> AnimatedImage? {
        let key = url.path as NSString
        if let cached = animationCache.object(forKey: key), cached.pixelSize >= maxPixelSize {
            return cached.animation
        }

        let budget = animationBudgetBytes
        let result = await Task.detached(priority: .userInitiated) { () -> (AnimatedImage, Int)? in
            Self.decodeAnimation(url: url, maxPixelSize: maxPixelSize, budgetBytes: budget)
        }.value

        guard let (animation, usedPixelSize) = result else { return nil }

        let cost = animation.frames.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        animationCache.setObject(
            CachedAnimation(animation: animation, pixelSize: usedPixelSize),
            forKey: key,
            cost: cost
        )
        return animation
    }

    /// Zahl der Einzelbilder in der Datei. Liest nur den Container-Header.
    public nonisolated static func frameCount(of url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    public nonisolated static func isAnimated(_ url: URL) -> Bool {
        frameCount(of: url) > 1
    }

    /// Dekodiert alle Frames und passt die Auflösung ans Speicherbudget an.
    ///
    /// - Returns: Animation und die tatsächlich verwendete Kantenlänge, oder `nil`
    ///   bei Einzelbildern und Lesefehlern.
    nonisolated static func decodeAnimation(
        url: URL,
        maxPixelSize: Int,
        budgetBytes: Int
    ) -> (AnimatedImage, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        // Native Grösse als Obergrenze: Hochskalieren beim Dekodieren bringt nichts
        // ausser Speicherverbrauch.
        var targetSize = maxPixelSize
        if let native = pixelSize(of: url) {
            targetSize = min(targetSize, Int(max(native.width, native.height)))
        }

        // Auflösung halbieren, bis alle Frames ins Budget passen. Die Untergrenze von
        // 320 px gilt nur fürs Herunterskalieren - ein nativ kleines Bild (Sticker,
        // kleines GIF) darf seine eigene Grösse behalten.
        let lowerBound = min(320, targetSize)
        while targetSize > lowerBound {
            if targetSize * targetSize * 4 * count <= budgetBytes { break }
            targetSize = max(targetSize / 2, lowerBound)
        }
        // Passt es selbst dann nicht, übernimmt der Standbild-Weg.
        guard targetSize * targetSize * 4 * count <= budgetBytes else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: targetSize,
        ]

        var frames: [CGImage] = []
        var delays: [Double] = []
        frames.reserveCapacity(count)
        delays.reserveCapacity(count)

        for index in 0..<count {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            frames.append(frame)
            delays.append(delay(of: source, at: index))
        }

        guard frames.count > 1 else { return nil }
        return (AnimatedImage(frames: frames, delays: delays), targetSize)
    }

    /// Liest die Anzeigedauer eines Frames. Die Formate legen sie jeweils in ihrem
    /// eigenen Property-Dictionary ab.
    private nonisolated static func delay(of source: CGImageSource, at index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return FrameTimeline.defaultDelay
        }

        let containers: [[CFString: Any]?] = [
            props[kCGImagePropertyWebPDictionary] as? [CFString: Any],
            props[kCGImagePropertyGIFDictionary] as? [CFString: Any],
            props[kCGImagePropertyPNGDictionary] as? [CFString: Any],
            props[kCGImagePropertyHEICSDictionary] as? [CFString: Any],
        ]
        let keys: [CFString] = [
            kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime,
            kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime,
            kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime,
            kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime,
        ]

        for container in containers.compactMap({ $0 }) {
            for key in keys {
                if let value = container[key] as? Double, value > 0 {
                    return value
                }
            }
        }
        return FrameTimeline.defaultDelay
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
