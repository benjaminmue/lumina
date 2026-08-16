import CoreGraphics
import LuminaCore
import SwiftUI

/// Zeigt ein einzelnes Bild samt Skalierungsmodus und Ken-Burns-Fahrt.
struct SlideLayerView: View {
    let slide: Slide
    let config: SlideshowConfig
    let isPaused: Bool

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
                    withAnimation(.linear(duration: config.slideDuration + config.transitionDuration)) {
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
                .aspectRatio(contentMode: contentMode)

        case .animated(let animation):
            AnimatedSlideView(animation: animation, contentMode: contentMode, isPaused: isPaused)
        }
    }
}

/// Spielt die Frames eines animierten Bildes ab (WebP, GIF, APNG).
///
/// `TimelineView(.animation)` taktet mit der Bildwiederholrate des Displays; der
/// sichtbare Frame ergibt sich aus der verstrichenen Zeit und den Frame-Delays.
private struct AnimatedSlideView: View {
    let animation: AnimatedImage
    let contentMode: ContentMode
    let isPaused: Bool

    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(paused: isPaused)) { context in
            let begin = start ?? context.date
            let elapsed = context.date.timeIntervalSince(begin)
            let frame = animation.frame(at: elapsed) ?? animation.first

            Group {
                if let frame {
                    Image(decorative: frame, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Color.clear
                }
            }
            .onAppear {
                // Zeitbasis erst beim ersten Frame setzen, sonst zählt die Ladezeit mit.
                if start == nil { start = context.date }
            }
        }
    }
}
