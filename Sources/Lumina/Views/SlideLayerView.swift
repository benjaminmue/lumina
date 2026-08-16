import LuminaCore
import SwiftUI

/// Zeigt ein einzelnes Bild samt Skalierungsmodus und Ken-Burns-Fahrt.
struct SlideLayerView: View {
    let slide: Slide
    let config: SlideshowConfig

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
                if config.scaleMode == .fitBlurred {
                    // Unscharfe, formatfüllende Kopie füllt die Letterbox-Ränder.
                    Image(decorative: slide.image, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 48, opaque: true)
                        .overlay(Color.black.opacity(0.35))
                        .clipped()
                }

                Image(decorative: slide.image, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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
}
