import CWebPDemux
import CoreGraphics
import Foundation

/// Dekodiert animierte WebP mit libwebp.
///
/// Apples ImageIO kann bei animierten WebP nur wahlfrei zugreifen und rechnet für
/// jeden Frame die gesamte Vorgeschichte neu - gemessen 280 ms je Frame bei einer
/// 301-Frame-Datei, also 3.6 fps. libwebp hält den Dekodier-Zustand und schafft
/// dieselbe Datei mit 1.5 ms je Frame.
/// Nicht threadsicher: die Instanz hält einen Dekodier-Cursor und gehört jeweils
/// genau einem Task. Darum bewusst nicht `Sendable`.
public final class WebPAnimationDecoder {
    /// Eigener Puffer für die Dateidaten.
    ///
    /// libwebp kopiert die Eingabe nicht, sondern merkt sich den Zeiger und liest
    /// später daraus. `Data.withUnsafeBytes` garantiert Gültigkeit ausdrücklich nur
    /// innerhalb des Closures - der Puffer muss darum uns gehören und exakt so lange
    /// leben wie der Decoder.
    private let buffer: UnsafeMutableBufferPointer<UInt8>
    private var decoder: OpaquePointer?
    private var lastTimestamp: Int32 = 0
    private var cursor = 0
    private let maxPixelSize: Int

    public let width: Int
    public let height: Int
    public let frameCount: Int
    /// Gesamtlaufzeit eines Durchlaufs in Sekunden.
    public let duration: Double

    /// - Parameter maxPixelSize: Längste Kante der gelieferten Frames. Grössere
    ///   Vorlagen werden verkleinert, sonst hängt der Speicherbedarf der Wiedergabe
    ///   allein an der Auflösung der Datei.
    /// - Returns: `nil`, wenn die Datei kein animiertes WebP ist.
    public init?(url: URL, maxPixelSize: Int) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty else { return nil }

        let owned = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: data.count)
        _ = data.copyBytes(to: owned)

        guard let probe = Self.makeDecoder(buffer: owned) else {
            owned.deallocate()
            return nil
        }
        var info = WebPAnimInfo()
        guard WebPAnimDecoderGetInfo(probe, &info) != 0, info.frame_count > 1 else {
            WebPAnimDecoderDelete(probe)
            owned.deallocate()
            return nil
        }

        self.buffer = owned
        self.maxPixelSize = maxPixelSize
        self.width = Int(info.canvas_width)
        self.height = Int(info.canvas_height)
        self.frameCount = Int(info.frame_count)
        self.duration = Self.readDuration(buffer: owned)
        self.decoder = probe
    }

    deinit {
        // Erst den Decoder freigeben, er liest bis dahin aus dem Puffer.
        if let decoder { WebPAnimDecoderDelete(decoder) }
        buffer.deallocate()
    }

    /// Liefert den nächsten Frame. Am Ende beginnt die Animation von vorne.
    public func next() -> TimedFrame? {
        guard let decoder else { return nil }

        if WebPAnimDecoderHasMoreFrames(decoder) == 0 {
            resetToStart()
        }

        var frameBuffer: UnsafeMutablePointer<UInt8>?
        var timestamp: Int32 = 0
        guard WebPAnimDecoderGetNext(decoder, &frameBuffer, &timestamp) != 0, let frameBuffer else {
            // Ohne Reset bliebe der Decoder an derselben Stelle stehen und der
            // Aufrufer würde endlos leere Frames abholen.
            resetToStart()
            return nil
        }

        // libwebp gibt seinen internen Puffer zurück und überschreibt ihn beim nächsten
        // Frame - die Daten müssen also kopiert werden.
        let copy = Data(bytes: frameBuffer, count: width * height * 4)

        // Der Zeitstempel markiert das Ende des Frames.
        let delaySeconds = Double(timestamp - lastTimestamp) / 1000.0
        lastTimestamp = timestamp

        guard let image = Self.makeImage(from: copy, width: width, height: height, maxPixelSize: maxPixelSize) else {
            return nil
        }

        let index = cursor
        cursor = (cursor + 1) % max(frameCount, 1)

        return TimedFrame(
            image: image,
            delay: delaySeconds < FrameTimeline.minimumDelay ? FrameTimeline.defaultDelay : delaySeconds,
            index: index
        )
    }

    public func rewind() {
        resetToStart()
    }

    private func resetToStart() {
        guard let decoder else { return }
        WebPAnimDecoderReset(decoder)
        lastTimestamp = 0
        cursor = 0
    }

    // MARK: - Intern

    private static func makeDecoder(buffer: UnsafeMutableBufferPointer<UInt8>) -> OpaquePointer? {
        var options = WebPAnimDecoderOptions()
        guard WebPAnimDecoderOptionsInit(&options) != 0 else { return nil }
        // MODE_bgrA passt direkt zu CoreGraphics (little endian, Alpha vormultipliziert).
        options.color_mode = MODE_bgrA
        options.use_threads = 1

        guard let base = buffer.baseAddress else { return nil }
        var webpData = WebPData(bytes: base, size: buffer.count)
        return WebPAnimDecoderNew(&webpData, &options)
    }

    /// Summiert die Frame-Dauern über den Demuxer, ohne Pixel zu dekodieren.
    ///
    /// Der Demuxer lebt nur innerhalb dieser Funktion, hier ist der geliehene
    /// Zeiger also unproblematisch.
    private static func readDuration(buffer: UnsafeMutableBufferPointer<UInt8>) -> Double {
        guard let base = buffer.baseAddress else { return 0 }
        var webpData = WebPData(bytes: base, size: buffer.count)
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

    /// Baut das CGImage und verkleinert es, falls die Vorlage grösser ist als nötig.
    ///
    /// Ohne diese Grenze bestimmt allein die Auflösung der Datei den Speicherbedarf:
    /// ein 4000x4000-Frame belegt 64 MB, mal Puffergrösse.
    private static func makeImage(from data: Data, width: Int, height: Int, maxPixelSize: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)

        guard let full = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }

        let longestEdge = max(width, height)
        guard longestEdge > maxPixelSize, maxPixelSize > 0 else { return full }

        let factor = Double(maxPixelSize) / Double(longestEdge)
        let targetWidth = max(Int((Double(width) * factor).rounded()), 1)
        let targetHeight = max(Int((Double(height) * factor).rounded()), 1)

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return full }

        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? full
    }
}
