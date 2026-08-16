import CoreGraphics
import Foundation
import ImageIO

/// Kopfdaten einer Bildanimation: Zahl der Frames und deren Anzeigedauern.
///
/// Wird ohne Pixel-Dekodierung gelesen und ist darum auch bei 400 Frames schnell.
public struct AnimationInfo: Equatable, Sendable {
    public let frameCount: Int
    public let timeline: FrameTimeline

    public var totalDuration: Double { timeline.totalDuration }
    public var isAnimated: Bool { frameCount > 1 }

    public init(frameCount: Int, delays: [Double]) {
        self.frameCount = frameCount
        self.timeline = FrameTimeline(delays: delays)
    }
}

/// Ein dekodierter Frame samt seiner Anzeigedauer.
public struct TimedFrame: @unchecked Sendable {
    public let image: CGImage
    public let delay: Double
    public let index: Int

    public init(image: CGImage, delay: Double, index: Int) {
        self.image = image
        self.delay = delay
        self.index = index
    }
}

/// Dekodiert die Frames einer Animation der Reihe nach.
///
/// WebP und GIF sind interframe-komprimiert: ein wahlfreier Zugriff auf Frame 300
/// zwingt ImageIO dazu, alle vorherigen mitzurechnen (gemessen 0.58 s gegenüber
/// 0.021 s beim sequenziellen Durchlauf). Darum wird strikt vorwärts gelesen und
/// die Quelle für einen neuen Durchlauf komplett neu geöffnet - genau so, wie es
/// Vorschau und QuickLook machen.
public final class AnimationDecoder: @unchecked Sendable {
    private let url: URL
    private let maxPixelSize: Int
    private var source: CGImageSource?
    private var cursor = 0
    /// Für WebP übernimmt libwebp; ImageIO wäre dort um Grössenordnungen langsamer.
    private let webp: WebPAnimationDecoder?

    public let info: AnimationInfo

    public init?(url: URL, maxPixelSize: Int) {
        guard let info = Self.readInfo(url: url), info.isAnimated else { return nil }
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.info = info
        self.webp = WebPAnimationDecoder(url: url)
        self.source = webp == nil ? CGImageSourceCreateWithURL(url as CFURL, nil) : nil
    }

    public var frameCount: Int { info.frameCount }

    /// Welcher Decoder tatsächlich arbeitet - für Diagnose und Tests.
    public var usesLibWebP: Bool { webp != nil }

    /// Liefert den nächsten Frame. Am Ende beginnt die Animation von vorne.
    public func next() -> TimedFrame? {
        if let webp { return webp.next() }

        if cursor >= info.frameCount { rewind() }
        guard let source, cursor < info.frameCount else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, cursor, options as CFDictionary) else {
            cursor += 1
            return nil
        }

        let frame = TimedFrame(
            image: image,
            delay: info.timeline.delays.indices.contains(cursor) ? info.timeline.delays[cursor] : FrameTimeline.defaultDelay,
            index: cursor
        )
        cursor += 1
        return frame
    }

    /// Setzt auf den Anfang zurück. Die Quelle wird neu geöffnet, weil ImageIO sonst
    /// den internen Dekodier-Zustand für den Rücksprung teuer neu aufbaut.
    public func rewind() {
        if let webp {
            webp.rewind()
            return
        }
        source = CGImageSourceCreateWithURL(url as CFURL, nil)
        cursor = 0
    }

    // MARK: - Kopfdaten

    /// Liest Frame-Anzahl und Delays, ohne Pixel zu dekodieren.
    public static func readInfo(url: URL) -> AnimationInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        let delays = (0..<count).map { delay(of: source, at: $0) }
        return AnimationInfo(frameCount: count, delays: delays)
    }

    /// Liest die Anzeigedauer eines Frames. Jedes Format legt sie in seinem eigenen
    /// Property-Dictionary ab.
    static func delay(of source: CGImageSource, at index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return FrameTimeline.defaultDelay
        }

        let containers = [
            props[kCGImagePropertyWebPDictionary] as? [CFString: Any],
            props[kCGImagePropertyGIFDictionary] as? [CFString: Any],
            props[kCGImagePropertyPNGDictionary] as? [CFString: Any],
            props[kCGImagePropertyHEICSDictionary] as? [CFString: Any],
        ].compactMap { $0 }

        let keys: [CFString] = [
            kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime,
            kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime,
            kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime,
            kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime,
        ]

        for container in containers {
            for key in keys {
                if let value = container[key] as? Double, value > 0 {
                    return value
                }
            }
        }
        return FrameTimeline.defaultDelay
    }
}
