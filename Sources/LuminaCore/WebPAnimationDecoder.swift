import CWebPDemux
import CoreGraphics
import Foundation

/// Dekodiert animierte WebP mit libwebp.
///
/// Apples ImageIO kann bei animierten WebP nur wahlfrei zugreifen und rechnet für
/// jeden Frame die gesamte Vorgeschichte neu - gemessen 280 ms je Frame bei einer
/// 301-Frame-Datei, also 3.6 fps. libwebp hält den Dekodier-Zustand und schafft
/// dieselbe Datei mit 1.5 ms je Frame.
public final class WebPAnimationDecoder: @unchecked Sendable {
    private let data: Data
    private var decoder: OpaquePointer?
    private var lastTimestamp: Int32 = 0

    public let width: Int
    public let height: Int
    public let frameCount: Int
    /// Gesamtlaufzeit eines Durchlaufs in Sekunden.
    public let duration: Double

    /// - Returns: `nil`, wenn die Datei kein animiertes WebP ist.
    public init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.data = data

        guard let probe = Self.makeDecoder(data: data) else { return nil }
        var info = WebPAnimInfo()
        guard WebPAnimDecoderGetInfo(probe, &info) != 0, info.frame_count > 1 else {
            WebPAnimDecoderDelete(probe)
            return nil
        }

        self.width = Int(info.canvas_width)
        self.height = Int(info.canvas_height)
        self.frameCount = Int(info.frame_count)
        self.duration = Self.readDuration(data: data)
        self.decoder = probe
    }

    deinit {
        if let decoder { WebPAnimDecoderDelete(decoder) }
    }

    /// Liefert den nächsten Frame. Am Ende beginnt die Animation von vorne.
    public func next() -> TimedFrame? {
        guard let decoder else { return nil }

        if WebPAnimDecoderHasMoreFrames(decoder) == 0 {
            WebPAnimDecoderReset(decoder)
            lastTimestamp = 0
        }

        var buffer: UnsafeMutablePointer<UInt8>?
        var timestamp: Int32 = 0
        guard WebPAnimDecoderGetNext(decoder, &buffer, &timestamp) != 0, let buffer else { return nil }

        // libwebp gibt seinen internen Puffer zurück und überschreibt ihn beim nächsten
        // Frame - die Daten müssen also kopiert werden.
        let byteCount = width * height * 4
        let copy = Data(bytes: buffer, count: byteCount)

        // Der Zeitstempel markiert das Ende des Frames.
        let delaySeconds = Double(timestamp - lastTimestamp) / 1000.0
        lastTimestamp = timestamp

        guard let image = Self.makeImage(from: copy, width: width, height: height) else { return nil }

        return TimedFrame(
            image: image,
            delay: delaySeconds < FrameTimeline.minimumDelay ? FrameTimeline.defaultDelay : delaySeconds,
            index: 0
        )
    }

    public func rewind() {
        guard let decoder else { return }
        WebPAnimDecoderReset(decoder)
        lastTimestamp = 0
    }

    // MARK: - Intern

    private static func makeDecoder(data: Data) -> OpaquePointer? {
        var options = WebPAnimDecoderOptions()
        guard WebPAnimDecoderOptionsInit(&options) != 0 else { return nil }
        // MODE_bgrA passt direkt zu CoreGraphics (little endian, Alpha vormultipliziert).
        options.color_mode = MODE_bgrA
        options.use_threads = 1

        return data.withUnsafeBytes { raw -> OpaquePointer? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var webpData = WebPData(bytes: base, size: raw.count)
            return WebPAnimDecoderNew(&webpData, &options)
        }
    }

    /// Summiert die Frame-Dauern über den Demuxer, ohne Pixel zu dekodieren.
    private static func readDuration(data: Data) -> Double {
        data.withUnsafeBytes { raw -> Double in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            var webpData = WebPData(bytes: base, size: raw.count)
            guard let demux = WebPDemux(&webpData) else { return 0 }
            defer { WebPDemuxDelete(demux) }

            let count = WebPDemuxGetI(demux, WEBP_FF_FRAME_COUNT)
            var total: Double = 0
            for index in 1...max(count, 1) {
                var iterator = WebPIterator()
                guard WebPDemuxGetFrame(demux, Int32(index), &iterator) != 0 else { break }
                let seconds = Double(iterator.duration) / 1000.0
                total += seconds < FrameTimeline.minimumDelay ? FrameTimeline.defaultDelay : seconds
                WebPDemuxReleaseIterator(&iterator)
            }
            return total
        }
    }

    private static func makeImage(from data: Data, width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                .union(.byteOrder32Little),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
