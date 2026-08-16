import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import LuminaCore

final class SlideshowConfigTests: XCTestCase {

    func testSanitizeClampsDurationsIntoRange() {
        var config = SlideshowConfig()
        config.slideDuration = 999
        config.transitionDuration = 42
        config.backgroundBrightness = 5

        let clean = config.sanitized()
        XCTAssertEqual(clean.slideDuration, SlideshowConfig.durationRange.upperBound)
        XCTAssertLessThanOrEqual(clean.transitionDuration, SlideshowConfig.transitionRange.upperBound)
        XCTAssertEqual(clean.backgroundBrightness, 1)
    }

    func testTransitionNeverOutlastsSlideDuration() {
        var config = SlideshowConfig()
        config.slideDuration = 2
        config.transitionDuration = 5

        let clean = config.sanitized()
        XCTAssertLessThanOrEqual(clean.transitionDuration, clean.slideDuration * 0.8)
    }

    func testDecodingToleratesMissingFields() throws {
        // Einstellungsdatei einer älteren Version: neue Felder fehlen.
        let json = """
        {"slideDuration": 7, "transition": "wipe", "loop": false}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(SlideshowConfig.self, from: json)
        XCTAssertEqual(config.slideDuration, 7)
        XCTAssertEqual(config.transition, .wipe)
        XCTAssertFalse(config.loop)
        // Nicht gespeicherte Felder müssen ihren Standardwert behalten.
        XCTAssertEqual(config.scaleMode, SlideshowConfig().scaleMode)
        XCTAssertEqual(config.playAnimationsFully, SlideshowConfig().playAnimationsFully)
    }

    func testConfigRoundtripsThroughJSON() throws {
        var config = SlideshowConfig()
        config.transition = .wipe
        config.scaleMode = .fitBlurred
        config.kenBurns = .strong
        config.sortOrder = .dateCreated

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SlideshowConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }
}

final class FrameTimelineTests: XCTestCase {

    func testTotalDurationIsSumOfDelays() {
        let timeline = FrameTimeline(delays: [0.1, 0.2, 0.3])
        XCTAssertEqual(timeline.totalDuration, 0.6, accuracy: 0.0001)
        XCTAssertEqual(timeline.frameCount, 3)
    }

    func testIndexPicksCorrectFrame() {
        let timeline = FrameTimeline(delays: [0.1, 0.2, 0.3])
        XCTAssertEqual(timeline.index(at: 0.0), 0)
        XCTAssertEqual(timeline.index(at: 0.05), 0)
        XCTAssertEqual(timeline.index(at: 0.15), 1)
        XCTAssertEqual(timeline.index(at: 0.25), 1)
        XCTAssertEqual(timeline.index(at: 0.35), 2)
        XCTAssertEqual(timeline.index(at: 0.59), 2)
    }

    func testTimelineWrapsAround() {
        let timeline = FrameTimeline(delays: [0.1, 0.2, 0.3])
        // Zweiter Durchlauf muss dieselben Frames liefern wie der erste.
        XCTAssertEqual(timeline.index(at: 0.65), timeline.index(at: 0.05))
        XCTAssertEqual(timeline.index(at: 1.25), timeline.index(at: 0.05))
        XCTAssertEqual(timeline.index(at: 0.95), timeline.index(at: 0.35))
    }

    func testNegativeTimeStaysInRange() {
        let timeline = FrameTimeline(delays: [0.1, 0.2, 0.3])
        let index = timeline.index(at: -0.05)
        XCTAssertTrue((0..<3).contains(index))
    }

    func testTinyDelaysAreNormalised() {
        // Alte GIFs schreiben oft 0 oder 0.01 - Viewer behandeln das als 0.1 s.
        let timeline = FrameTimeline(delays: [0, 0.005, 0.01])
        XCTAssertEqual(timeline.delays, [0.1, 0.1, 0.1])
        XCTAssertEqual(timeline.totalDuration, 0.3, accuracy: 0.0001)
    }

    func testSingleFrameAlwaysReturnsZero() {
        let timeline = FrameTimeline(delays: [0.2])
        XCTAssertEqual(timeline.index(at: 0), 0)
        XCTAssertEqual(timeline.index(at: 99), 0)
    }

    func testEmptyTimelineIsSafe() {
        let timeline = FrameTimeline(delays: [])
        XCTAssertEqual(timeline.frameCount, 0)
        XCTAssertEqual(timeline.totalDuration, 0)
        XCTAssertEqual(timeline.index(at: 1.5), 0)
    }

    func testIndexIsStableAcrossManyFrames() {
        // Cinemagraph-Grössenordnung. Geprüft wird jeweils die Frame-Mitte: genau auf
        // einer Frame-Grenze ist wegen der Gleitkomma-Summe beides vertretbar.
        let timeline = FrameTimeline(delays: Array(repeating: 0.04, count: 250))
        XCTAssertEqual(timeline.index(at: 0.02), 0)
        XCTAssertEqual(timeline.index(at: 4.02), 100)
        XCTAssertEqual(timeline.index(at: 9.98), 249)
        XCTAssertEqual(timeline.totalDuration, 10.0, accuracy: 0.001)
    }
}

final class TransitionStyleTests: XCTestCase {

    func testRandomResolvesToConcreteStyle() {
        let resolved = TransitionStyle.random.resolved(seed: 12345)
        XCTAssertNotEqual(resolved, .random)
        XCTAssertNotEqual(resolved, .cut)
        XCTAssertTrue(TransitionStyle.concreteStyles.contains(resolved))
    }

    func testRandomIsStableForSameSeed() {
        let a = TransitionStyle.random.resolved(seed: 987)
        let b = TransitionStyle.random.resolved(seed: 987)
        XCTAssertEqual(a, b)
    }

    func testNonRandomStylesPassThrough() {
        for style in TransitionStyle.allCases where style != .random {
            XCTAssertEqual(style.resolved(seed: 1), style)
        }
    }
}

final class SeededGeneratorTests: XCTestCase {

    func testSameSeedProducesSameSequence() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        let first = (0..<10).map { _ in a.next() }
        let second = (0..<10).map { _ in b.next() }
        XCTAssertEqual(first, second)
    }

    func testDifferentSeedsDiverge() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        XCTAssertNotEqual(a.next(), b.next())
    }

    func testStableHashIsDeterministicAcrossCalls() {
        XCTAssertEqual("/Users/test/bild.jpg".stableHash, "/Users/test/bild.jpg".stableHash)
        XCTAssertNotEqual("/Users/test/a.jpg".stableHash, "/Users/test/b.jpg".stableHash)
    }
}

final class KenBurnsPlanTests: XCTestCase {

    func testOffProducesStillImage() {
        let plan = KenBurnsPlan.make(seed: 7, intensity: .off)
        XCTAssertEqual(plan, .still)
    }

    func testPlanIsReproducible() {
        let a = KenBurnsPlan.make(seed: 99, intensity: .medium)
        let b = KenBurnsPlan.make(seed: 99, intensity: .medium)
        XCTAssertEqual(a, b)
    }

    func testScalesNeverShrinkBelowOne() {
        for seed in UInt64(1)...50 {
            for intensity in KenBurnsIntensity.allCases {
                let plan = KenBurnsPlan.make(seed: seed, intensity: intensity)
                XCTAssertGreaterThanOrEqual(plan.startScale, 1, "Seed \(seed) / \(intensity)")
                XCTAssertGreaterThanOrEqual(plan.endScale, 1, "Seed \(seed) / \(intensity)")
            }
        }
    }

    func testStrongerIntensityZoomsFurther() {
        // Über viele Seeds gemittelt muss "stark" deutlich mehr Zoom liefern als "dezent".
        func averageZoom(_ intensity: KenBurnsIntensity) -> Double {
            let plans = (UInt64(1)...100).map { KenBurnsPlan.make(seed: $0, intensity: intensity) }
            return plans.reduce(0.0) { $0 + Double(max($1.startScale, $1.endScale)) } / Double(plans.count)
        }
        XCTAssertGreaterThan(averageZoom(.strong), averageZoom(.subtle))
        XCTAssertGreaterThan(averageZoom(.medium), averageZoom(.subtle))
    }

    func testPanStaysWithinConfiguredAmount() {
        for seed in UInt64(1)...50 {
            let plan = KenBurnsPlan.make(seed: seed, intensity: .strong)
            let travelX = abs(plan.endOffset.width - plan.startOffset.width)
            let travelY = abs(plan.endOffset.height - plan.startOffset.height)
            XCTAssertLessThanOrEqual(hypot(travelX, travelY), KenBurnsIntensity.strong.panAmount + 0.001)
        }
    }
}

final class SlideshowSequenceTests: XCTestCase {

    private func items(_ count: Int) -> [MediaItem] {
        (0..<count).map { index in
            MediaItem(
                url: URL(fileURLWithPath: "/tmp/lumina/bild-\(index).jpg"),
                name: "bild-\(index).jpg",
                creationDate: Date(timeIntervalSince1970: TimeInterval(index)),
                modificationDate: Date(timeIntervalSince1970: TimeInterval(100 - index)),
                fileSize: Int64((count - index) * 1000)
            )
        }
    }

    func testAdvanceStopsAtEndWithoutLoop() {
        var sequence = SlideshowSequence(items: items(3))
        XCTAssertTrue(sequence.advance(loop: false))
        XCTAssertTrue(sequence.advance(loop: false))
        XCTAssertFalse(sequence.advance(loop: false))
        XCTAssertEqual(sequence.index, 2)
    }

    func testAdvanceWrapsWithLoop() {
        var sequence = SlideshowSequence(items: items(2))
        sequence.advance(loop: true)
        XCTAssertTrue(sequence.advance(loop: true))
        XCTAssertEqual(sequence.index, 0)
    }

    func testRewindWrapsToEnd() {
        var sequence = SlideshowSequence(items: items(3))
        sequence.rewind()
        XCTAssertEqual(sequence.index, 2)
        XCTAssertEqual(sequence.lastDirection, .backward)
    }

    func testEmptySequenceIsSafe() {
        var sequence = SlideshowSequence(items: [])
        XCTAssertNil(sequence.current)
        XCTAssertFalse(sequence.advance(loop: true))
        sequence.rewind()
        XCTAssertTrue(sequence.upcomingURLs(count: 3).isEmpty)
    }

    func testStartIndexIsClamped() {
        let sequence = SlideshowSequence(items: items(3), startIndex: 99)
        XCTAssertEqual(sequence.index, 2)
    }

    func testUpcomingURLsSkipCurrentAndWrap() {
        let sequence = SlideshowSequence(items: items(3), startIndex: 2)
        let upcoming = sequence.upcomingURLs(count: 2)
        XCTAssertEqual(upcoming.map(\.lastPathComponent), ["bild-0.jpg", "bild-1.jpg"])
    }

    func testUpcomingURLsNeverRepeatCurrentInSingleItemList() {
        let sequence = SlideshowSequence(items: items(1))
        XCTAssertTrue(sequence.upcomingURLs(count: 3).isEmpty)
    }
}

final class AnimationDecodingTests: XCTestCase {

    /// Baut ein echtes animiertes GIF, damit der Dekodier-Pfad mit einer Datei
    /// geprüft wird und nicht nur mit erdachten Werten.
    private func makeAnimatedGIF(frames: Int, delay: Double, size: Int = 400) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-anim-\(UUID().uuidString).gif")

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames, nil
        ) else {
            throw XCTSkip("GIF-Encoder nicht verfügbar")
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        for index in 0..<frames {
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let shade = CGFloat(index) / CGFloat(max(frames - 1, 1))
            context.setFillColor(CGColor(red: shade, green: 0.2, blue: 1 - shade, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))

            CGImageDestinationAddImage(destination, context.makeImage()!, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay],
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("GIF konnte nicht geschrieben werden")
        }
        return url
    }

    func testAnimatedFileIsDetected() throws {
        let url = try makeAnimatedGIF(frames: 5, delay: 0.2)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(ImageLoader.frameCount(of: url), 5)
        XCTAssertTrue(ImageLoader.isAnimated(url))
    }

    func testAllFramesAndDelaysAreDecoded() throws {
        let url = try makeAnimatedGIF(frames: 5, delay: 0.2)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ImageLoader.decodeAnimation(url: url, maxPixelSize: 800, budgetBytes: 256 * 1024 * 1024)
        let animation = try XCTUnwrap(result?.0)

        XCTAssertEqual(animation.frameCount, 5)
        XCTAssertEqual(animation.totalDuration, 1.0, accuracy: 0.05)
        // Frames müssen sich unterscheiden - sonst wäre wieder nur Index 0 geladen.
        XCTAssertFalse(animation.frame(at: 0.0) === animation.frame(at: 0.5))
    }

    func testStillImageYieldsNoAnimation() throws {
        let url = try makeAnimatedGIF(frames: 1, delay: 0.2)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(ImageLoader.isAnimated(url))
        XCTAssertNil(ImageLoader.decodeAnimation(url: url, maxPixelSize: 800, budgetBytes: 256 * 1024 * 1024))
    }

    func testDecodeNeverExceedsMemoryBudget() throws {
        let url = try makeAnimatedGIF(frames: 20, delay: 0.05, size: 1200)
        defer { try? FileManager.default.removeItem(at: url) }

        let budget = 24 * 1024 * 1024
        let result = ImageLoader.decodeAnimation(url: url, maxPixelSize: 2560, budgetBytes: budget)

        if let (animation, usedSize) = result {
            let bytes = animation.frames.reduce(0) { $0 + $1.bytesPerRow * $1.height }
            XCTAssertLessThanOrEqual(bytes, budget, "Dekodierte Frames sprengen das Budget")
            XCTAssertLessThanOrEqual(usedSize, 1200, "Nie über die native Auflösung hinaus dekodieren")
        }
        // Kein Ergebnis ist zulässig: dann fällt der Player auf das Standbild zurück.
    }

    func testDecodeDoesNotUpscaleBeyondNativeSize() throws {
        let url = try makeAnimatedGIF(frames: 3, delay: 0.1, size: 200)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ImageLoader.decodeAnimation(url: url, maxPixelSize: 4000, budgetBytes: 256 * 1024 * 1024)
        let frame = try XCTUnwrap(result?.0.first)
        XCTAssertLessThanOrEqual(frame.width, 200)
    }
}

final class MediaScannerTests: XCTestCase {

    func testSupportedExtensionsAreRecognised() {
        XCTAssertTrue(MediaScanner.isSupportedImage(URL(fileURLWithPath: "/tmp/a.JPG")))
        XCTAssertTrue(MediaScanner.isSupportedImage(URL(fileURLWithPath: "/tmp/a.heic")))
        XCTAssertTrue(MediaScanner.isSupportedImage(URL(fileURLWithPath: "/tmp/a.png")))
        XCTAssertFalse(MediaScanner.isSupportedImage(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertFalse(MediaScanner.isSupportedImage(URL(fileURLWithPath: "/tmp/a.txt")))
        XCTAssertFalse(MediaScanner.isSupportedImage(URL(fileURLWithPath: "/tmp/a.mp4")))
    }

    func testCollectFindsImagesRecursivelyAndSkipsOtherFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-test-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("unterordner")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data([0x1]).write(to: root.appendingPathComponent("a.jpg"))
        try Data([0x1]).write(to: root.appendingPathComponent("notiz.txt"))
        try Data([0x1]).write(to: sub.appendingPathComponent("b.png"))

        let recursive = MediaScanner.collect(from: [root], recursive: true)
        XCTAssertEqual(Set(recursive.map(\.name)), ["a.jpg", "b.png"])

        let flat = MediaScanner.collect(from: [root], recursive: false)
        XCTAssertEqual(flat.map(\.name), ["a.jpg"])
    }

    func testCollectDeduplicatesOverlappingSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("a.jpg")
        try Data([0x1]).write(to: file)

        // Ordner und die darin enthaltene Datei gleichzeitig als Quelle angegeben.
        let items = MediaScanner.collect(from: [root, file], recursive: true)
        XCTAssertEqual(items.count, 1)
    }

    func testSortByNameUsesNaturalOrdering() {
        let names = ["bild-2.jpg", "bild-10.jpg", "bild-1.jpg"]
        let items = names.map {
            MediaItem(url: URL(fileURLWithPath: "/tmp/\($0)"), name: $0, creationDate: nil, modificationDate: nil, fileSize: 0)
        }
        let sorted = MediaScanner.sort(items, by: .name, ascending: true)
        XCTAssertEqual(sorted.map(\.name), ["bild-1.jpg", "bild-2.jpg", "bild-10.jpg"])
    }

    func testSortDescendingReversesOrder() {
        let items = (1...3).map {
            MediaItem(
                url: URL(fileURLWithPath: "/tmp/\($0).jpg"),
                name: "\($0).jpg",
                creationDate: Date(timeIntervalSince1970: TimeInterval($0)),
                modificationDate: nil,
                fileSize: 0
            )
        }
        let sorted = MediaScanner.sort(items, by: .dateCreated, ascending: false)
        XCTAssertEqual(sorted.map(\.name), ["3.jpg", "2.jpg", "1.jpg"])
    }

    func testShuffleIsStableForSameSeedAndKeepsAllItems() {
        let items = (1...20).map {
            MediaItem(url: URL(fileURLWithPath: "/tmp/\($0).jpg"), name: "\($0).jpg", creationDate: nil, modificationDate: nil, fileSize: 0)
        }
        let a = MediaScanner.sort(items, by: .shuffled, ascending: true, seed: 4711)
        let b = MediaScanner.sort(items, by: .shuffled, ascending: true, seed: 4711)
        let c = MediaScanner.sort(items, by: .shuffled, ascending: true, seed: 1234)

        XCTAssertEqual(a.map(\.name), b.map(\.name))
        XCTAssertNotEqual(a.map(\.name), c.map(\.name))
        XCTAssertEqual(Set(a.map(\.name)), Set(items.map(\.name)))
    }
}
