import CoreGraphics
import Foundation
import LuminaCore
import SwiftUI

/// Ein sichtbares Bild samt aufgelöstem Übergang.
///
/// `id` zählt hoch statt die URL zu spiegeln, damit SwiftUI auch dann einen Wechsel
/// animiert, wenn dasselbe Bild zweimal hintereinander erscheint (Liste mit einem Bild).
struct Slide: Identifiable, Equatable {
    let id: Int
    let item: MediaItem
    let image: CGImage
    let transition: TransitionStyle
    let direction: SlideshowSequence.Direction

    static func == (lhs: Slide, rhs: Slide) -> Bool { lhs.id == rhs.id }
}

/// Steuert den Ablauf der laufenden Slideshow: Timing, Vor- und Zurückspringen,
/// Pause und das Nachladen der Bilder.
@MainActor
final class SlideshowEngine: ObservableObject {
    @Published private(set) var slide: Slide?
    @Published private(set) var sequence: SlideshowSequence
    @Published private(set) var isPaused = false
    @Published private(set) var isLoading = false
    /// Fortschritt der aktuellen Standzeit, 0...1.
    @Published private(set) var progress: Double = 0
    /// Wird gesetzt, wenn ohne Loop das letzte Bild gezeigt wurde.
    @Published private(set) var didFinish = false

    /// Zielauflösung fürs Dekodieren. Wird vom Player anhand der Fenstergrösse gesetzt.
    var targetPixelSize: Int = 2560

    private enum Command {
        case next
        case previous
        case jump(Int)
    }

    private let loader: ImageLoader
    private var config: SlideshowConfig
    private var loopTask: Task<Void, Never>?
    private var pending: Command?
    private var slideCounter = 0
    private let tick = Duration.milliseconds(40)

    init(items: [MediaItem], config: SlideshowConfig, loader: ImageLoader, startIndex: Int = 0) {
        self.sequence = SlideshowSequence(items: items, startIndex: startIndex)
        self.config = config
        self.loader = loader
    }

    var currentIndex: Int { sequence.index }
    var count: Int { sequence.count }

    /// Übernimmt geänderte Einstellungen im laufenden Betrieb.
    func update(config newConfig: SlideshowConfig) {
        config = newConfig
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in await self?.run() }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func togglePause() { isPaused.toggle() }
    func pause() { isPaused = true }
    func resume() { isPaused = false }

    func next() { pending = .next }
    func previous() { pending = .previous }
    func jump(to index: Int) { pending = .jump(index) }

    // MARK: - Ablauf

    private func run() async {
        guard !sequence.isEmpty else { return }
        await present(transitionStyle: .cut)

        var elapsed: Double = 0
        var lastTick = ContinuousClock.now

        while !Task.isCancelled {
            try? await Task.sleep(for: tick)
            if Task.isCancelled { break }

            let now = ContinuousClock.now
            let delta = Double((now - lastTick).components.attoseconds) / 1e18
                + Double((now - lastTick).components.seconds)
            lastTick = now

            if let command = pending {
                pending = nil
                await handle(command)
                elapsed = 0
                continue
            }

            guard !isPaused, !didFinish else { continue }

            elapsed += delta
            progress = min(elapsed / max(config.slideDuration, 0.1), 1)

            if elapsed >= config.slideDuration {
                elapsed = 0
                guard sequence.advance(loop: config.loop) else {
                    didFinish = true
                    continue
                }
                await present(transitionStyle: config.transition)
            }
        }
    }

    private func handle(_ command: Command) async {
        didFinish = false
        switch command {
        case .next:
            // Manuelles Weiterschalten läuft immer im Kreis, auch ohne Loop-Einstellung.
            sequence.advance(loop: true)
        case .previous:
            sequence.rewind()
        case .jump(let index):
            sequence.jump(to: index)
        }
        await present(transitionStyle: config.transition)
    }

    /// Lädt das Bild am aktuellen Index und blendet es ein.
    private func present(transitionStyle: TransitionStyle) async {
        guard let item = sequence.current else { return }

        isLoading = true
        let image = await loader.image(for: item.url, maxPixelSize: targetPixelSize)
        isLoading = false

        guard let image else {
            // Defekte oder gelöschte Datei: überspringen, aber Endlosschleife vermeiden.
            if sequence.count > 1, sequence.advance(loop: config.loop) {
                await present(transitionStyle: transitionStyle)
            }
            return
        }

        slideCounter += 1
        let resolved = transitionStyle.resolved(seed: item.seed &+ UInt64(slideCounter))
        let newSlide = Slide(
            id: slideCounter,
            item: item,
            image: image,
            transition: resolved,
            direction: sequence.lastDirection
        )

        progress = 0
        let duration = transitionStyle == .cut ? 0 : config.transitionDuration
        if duration > 0 {
            withAnimation(.easeInOut(duration: duration)) { slide = newSlide }
        } else {
            slide = newSlide
        }

        await loader.prefetch(sequence.upcomingURLs(count: 2), maxPixelSize: targetPixelSize)
    }
}
