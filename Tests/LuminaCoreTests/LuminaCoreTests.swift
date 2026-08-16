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
