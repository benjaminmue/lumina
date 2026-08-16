import CoreGraphics
import Foundation
import LuminaCore
import SwiftUI

/// Ein sichtbares Bild samt aufgelöstem Übergang.
///
/// `id` zählt hoch statt die URL zu spiegeln, damit SwiftUI auch dann einen Wechsel
/// animiert, wenn dasselbe Bild zweimal hintereinander erscheint (Liste mit einem Bild).
/// Bildinhalt eines Slides: Standbild oder Animation (WebP, GIF, APNG).
///
/// Animationen halten keine Frames, sondern nur das erste Bild und die Quelle -
/// abgespielt wird im Stream. Ein Cinemagraph mit 400 Frames erscheint dadurch
/// genauso schnell wie ein JPEG.
enum SlideContent {
    case still(CGImage)
    case animated(poster: CGImage, url: URL, info: AnimationInfo)

    /// Standbild für Übergänge, Unschärfe-Hintergrund und als Rückfallebene.
    var representative: CGImage? {
        switch self {
        case .still(let image): return image
        case .animated(let poster, _, _): return poster
        }
    }

    var animationDuration: Double {
        switch self {
        case .still: return 0
        case .animated(_, _, let info): return info.totalDuration
        }
    }
}

struct Slide: Identifiable, Equatable {
    let id: Int
    let item: MediaItem
    let content: SlideContent
    let transition: TransitionStyle
    let direction: SlideshowSequence.Direction

    /// Der Vergleich zieht das Bild mit heran, damit ein Nachladen in höherer Auflösung
    /// die View aktualisiert. Über `id` allein würde SwiftUI das Update verwerfen.
    static func == (lhs: Slide, rhs: Slide) -> Bool {
        lhs.id == rhs.id && lhs.content.representative === rhs.content.representative
    }
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
    /// Standzeit des laufenden Slides. Weicht von der Einstellung ab, wenn eine
    /// Animation vollständig abgespielt wird.
    @Published private(set) var currentSlideDuration: Double = 5

    /// Zielauflösung fürs Dekodieren. Wird vom Player anhand der Fenstergrösse gesetzt.
    private(set) var targetPixelSize: Int = 2560

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
        self.currentSlideDuration = config.slideDuration
    }

    var currentIndex: Int { sequence.index }
    var count: Int { sequence.count }

    /// Übernimmt geänderte Einstellungen im laufenden Betrieb.
    func update(config newConfig: SlideshowConfig) {
        config = newConfig
    }

    /// Setzt die Zielauflösung, etwa nach dem Wechsel in den Vollbildmodus.
    ///
    /// Wird die Fläche grösser, wird das laufende Bild sofort in besserer Auflösung
    /// nachgeladen - sonst bliebe es bis zum nächsten Wechsel sichtbar unscharf.
    func setTargetPixelSize(_ size: Int) async {
        guard size > targetPixelSize else { return }
        targetPixelSize = size

        // Nur Standbilder werden nachgeschärft: bei einer Animation müssten alle Frames
        // neu dekodiert werden, was mitten in der Wiedergabe stocken würde.
        guard let current = slide,
              case .still = current.content,
              let sharper = await loader.image(for: current.item.url, maxPixelSize: size)
        else { return }

        // Gleiche id: die View wird aktualisiert statt ersetzt, die Ken-Burns-Fahrt läuft weiter.
        slide = Slide(
            id: current.id,
            item: current.item,
            content: .still(sharper),
            transition: current.transition,
            direction: current.direction
        )
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
            progress = min(elapsed / max(currentSlideDuration, 0.1), 1)

            if elapsed >= currentSlideDuration {
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
        let content = await load(item: item)
        isLoading = false

        guard let content else {
            // Defekte oder gelöschte Datei: überspringen, aber Endlosschleife vermeiden.
            if sequence.count > 1, sequence.advance(loop: config.loop) {
                await present(transitionStyle: transitionStyle)
            }
            return
        }

        currentSlideDuration = slideDuration(for: content)
        slideCounter += 1
        let resolved = transitionStyle.resolved(seed: item.seed &+ UInt64(slideCounter))
        let newSlide = Slide(
            id: slideCounter,
            item: item,
            content: content,
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

    /// Lädt das Standbild und - bei animierten Dateien - die Kopfdaten der Animation.
    ///
    /// Beides ist billig: das erste Bild wird direkt in Zielgrösse dekodiert, die
    /// Kopfdaten kosten keine Pixel-Dekodierung. Die Frames holt der Player selbst.
    private func load(item: MediaItem) async -> SlideContent? {
        guard let poster = await loader.image(for: item.url, maxPixelSize: targetPixelSize) else { return nil }

        if let info = await loader.animationInfo(for: item.url), info.isAnimated {
            return .animated(poster: poster, url: item.url, info: info)
        }
        return .still(poster)
    }

    /// Standzeit des aktuellen Slides.
    ///
    /// Animationen dürfen auf Wunsch zu Ende laufen, damit ein Cinemagraph nicht
    /// mitten in der Bewegung abgeschnitten wird.
    private func slideDuration(for content: SlideContent) -> Double {
        guard config.playAnimationsFully, content.animationDuration > 0 else {
            return config.slideDuration
        }
        // Volle Durchläufe zählen, damit die Animation an ihrem Anfang endet.
        let loops = max(1, (config.slideDuration / content.animationDuration).rounded())
        return min(content.animationDuration * loops, SlideshowConfig.durationRange.upperBound)
    }
}
