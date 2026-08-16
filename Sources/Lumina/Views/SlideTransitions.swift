import LuminaCore
import SwiftUI

/// Baut die SwiftUI-Übergänge für die einzelnen Effekt-Stile.
enum SlideTransitions {

    static func transition(
        for style: TransitionStyle,
        direction: SlideshowSequence.Direction,
        duration: Double
    ) -> AnyTransition {
        let forward = direction == .forward
        let incomingEdge: Edge = forward ? .trailing : .leading
        let outgoingEdge: Edge = forward ? .leading : .trailing

        switch style {
        case .cut, .random:
            // `.random` ist zu diesem Zeitpunkt bereits aufgelöst; der Fall bleibt als Fallback.
            return .identity

        case .crossfade:
            return .opacity

        case .slide:
            // Das neue Bild schiebt sich über das alte, das alte bleibt liegen und blendet aus.
            return .asymmetric(
                insertion: .move(edge: incomingEdge),
                removal: .opacity
            )

        case .push:
            // Beide Bilder bewegen sich gemeinsam - wie ein Filmstreifen.
            return .asymmetric(
                insertion: .move(edge: incomingEdge),
                removal: .move(edge: outgoingEdge)
            )

        case .zoomBlur:
            return .asymmetric(
                insertion: .scale(scale: 1.18).combined(with: .opacity),
                removal: .scale(scale: 0.88).combined(with: .opacity)
            )

        case .wipe:
            return .asymmetric(
                insertion: .modifier(
                    active: WipeMask(progress: 0, edge: incomingEdge),
                    identity: WipeMask(progress: 1, edge: incomingEdge)
                ),
                removal: .opacity
            )

        case .flip:
            // Zwei Halbphasen: das alte Bild dreht weg, danach dreht das neue herein.
            let half = max(duration / 2, 0.05)
            return .asymmetric(
                insertion: .modifier(
                    active: FlipEffect(angle: forward ? 90 : -90),
                    identity: FlipEffect(angle: 0)
                ).animation(.easeOut(duration: half).delay(half)),
                removal: .modifier(
                    active: FlipEffect(angle: forward ? -90 : 90),
                    identity: FlipEffect(angle: 0)
                ).animation(.easeIn(duration: half))
            )
        }
    }
}

/// Blendet den Inhalt über eine wachsende Rechteck-Maske ein.
private struct WipeMask: ViewModifier, Animatable {
    var progress: Double
    let edge: Edge

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var alignment: Alignment {
        switch edge {
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    func body(content: Content) -> some View {
        content.mask(alignment: alignment) {
            GeometryReader { geo in
                let clamped = min(max(progress, 0), 1)
                Rectangle()
                    .frame(
                        width: edge == .top || edge == .bottom ? geo.size.width : geo.size.width * clamped,
                        height: edge == .leading || edge == .trailing ? geo.size.height : geo.size.height * clamped
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            }
        }
    }
}

/// Dreht den Inhalt um die vertikale Achse.
private struct FlipEffect: ViewModifier, Animatable {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            // Ab etwa 80 Grad sieht man die Kante - dort ausblenden statt eine Papierkante zu zeigen.
            .opacity(abs(angle) > 80 ? 0 : 1)
    }
}
