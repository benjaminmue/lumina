import CoreGraphics
import LuminaCore
import SwiftUI

/// Zeigt ein einzelnes Bild samt Skalierungsmodus und Ken-Burns-Fahrt.
struct SlideLayerView: View {
    let slide: Slide
    let config: SlideshowConfig
    /// Tatsächliche Standzeit dieses Bildes. Weicht von `config.slideDuration` ab,
    /// wenn eine Animation ganz abgespielt wird - ohne das stünde die Kamerafahrt
    /// den Rest der Zeit still.
    let slideDuration: Double
    let isPaused: Bool
    /// Zielauflösung fürs Dekodieren der Animations-Frames.
    let maxPixelSize: Int

    @State private var atEnd = false

    private var plan: KenBurnsPlan {
        KenBurnsPlan.make(seed: slide.item.seed, intensity: config.kenBurns)
    }

    private var contentMode: ContentMode {
        config.scaleMode == .fill ? .fill : .fit
    }

    var body: some View {
        GeometryReader { geo in
            let plan = plan
            let scale = atEnd ? plan.endScale : plan.startScale
            let offset = atEnd ? plan.endOffset : plan.startOffset

            ZStack {
                if config.scaleMode == .fitBlurred, let backdrop = slide.content.representative {
                    // Unscharfe, formatfüllende Kopie füllt die Letterbox-Ränder.
                    // Bei Animationen genügt dafür der erste Frame.
                    Image(decorative: backdrop, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 48, opaque: true)
                        .overlay(Color.black.opacity(0.35))
                        .clipped()
                }

                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(
                        x: geo.size.width * offset.width,
                        y: geo.size.height * offset.height
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .onAppear {
                guard config.kenBurns != .off else { return }
                // Der Startzustand muss einmal gerendert sein, sonst springt das Bild
                // ohne Animation direkt in die Endlage.
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: slideDuration + config.transitionDuration)) {
                        atEnd = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch slide.content {
        case .still(let image):
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                // Viele Cinemagraphs sind nur wenige hundert Pixel breit und müssen
                // stark vergrössert werden - die bessere Interpolation lohnt sich.
                .interpolation(.high)
                .aspectRatio(contentMode: contentMode)

        case .animated(let poster, let url, _):
            AnimatedSlideView(
                url: url,
                poster: poster,
                maxPixelSize: maxPixelSize,
                contentMode: contentMode,
                isPaused: isPaused
            )
        }
    }
}

/// Spielt eine animierte Datei im Stream ab und zeigt bis zum ersten dekodierten
/// Frame das Standbild - dadurch ist sofort etwas zu sehen.
private struct AnimatedSlideView: View {
    let url: URL
    let poster: CGImage
    let maxPixelSize: Int
    let contentMode: ContentMode
    let isPaused: Bool

    @StateObject private var playback: AnimationPlayback

    init(url: URL, poster: CGImage, maxPixelSize: Int, contentMode: ContentMode, isPaused: Bool) {
        self.url = url
        self.poster = poster
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.isPaused = isPaused
        _playback = StateObject(
            wrappedValue: AnimationPlayback(url: url, maxPixelSize: maxPixelSize, isPaused: isPaused)
        )
    }

    var body: some View {
        Image(decorative: playback.frame ?? poster, scale: 1, orientation: .up)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: contentMode)
            .onAppear { playback.start() }
            .onDisappear { playback.stop() }
            .onChange(of: isPaused) { _, paused in playback.setPaused(paused) }
    }
}
