import SwiftUI

/// Schwebende Steuerleiste des Players.
///
/// Bewusst ohne Kenntnis der Engine, damit sie sich für Bildschirmfotos auch mit
/// erfundenen Werten rendern lässt.
struct PlayerControls: View {

    struct State {
        var index: Int
        var count: Int
        var isPaused: Bool
        var title: String
        var didFinish: Bool
    }

    struct Actions {
        var previous: () -> Void
        var togglePause: () -> Void
        var next: () -> Void
        var restart: () -> Void
        var exit: () -> Void

        /// Für Bildschirmfotos: sichtbar, aber ohne Wirkung.
        static let inert = Actions(
            previous: {}, togglePause: {}, next: {}, restart: {}, exit: {}
        )
    }

    let state: State
    let actions: Actions
    var showsTitle: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Verlauf und Schatten brauchen die volle Fläche. Lag der Verlauf im
            // Hintergrund des Inhalts, war er nur so breit wie die Kapsel und der
            // Schatten wurde an derselben Kante abgeschnitten.
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            content
                .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var content: some View {
        VStack(spacing: 12) {
            if showsTitle {
                Text(state.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.35), in: Capsule())
            }

            HStack(spacing: 20) {
                if state.didFinish {
                    // Am Ende der Show übernimmt dieselbe Leiste - kein Dialog mitten im Bild.
                    Button(action: actions.restart) {
                        Label("Von vorne", systemImage: "arrow.counterclockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.callout)
                } else {
                    Button(action: actions.previous) {
                        Image(systemName: "backward.fill")
                    }
                    .help("Vorheriges Bild (Pfeil links)")

                    Button(action: actions.togglePause) {
                        Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                            .frame(width: 20)
                    }
                    .help("Pause und Weiter (Leertaste)")

                    Button(action: actions.next) {
                        Image(systemName: "forward.fill")
                    }
                    .help("Nächstes Bild (Pfeil rechts)")

                    Text("\(state.index + 1) / \(state.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.leading, 4)
                }

                Divider().frame(height: 16).overlay(.white.opacity(0.2))

                Button(action: actions.exit) {
                    Image(systemName: "xmark")
                }
                .help("Slideshow beenden (Esc)")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
            .font(.title3)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        }
    }
}
