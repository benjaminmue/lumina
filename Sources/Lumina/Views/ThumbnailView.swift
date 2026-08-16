import AppKit
import CoreGraphics
import LuminaCore
import SwiftUI

/// Vorschaukachel im Hauptfenster. Klick schaltet das Bild für die Slideshow an oder aus.
struct ThumbnailView: View {
    let item: MediaItem
    let loader: ImageLoader
    let isEnabled: Bool
    let onToggle: () -> Void
    let onPlayFromHere: () -> Void

    @State private var image: CGImage?
    @State private var frameCount = 1

    var body: some View {
        Button(action: onToggle) {
            tile
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityValue(isEnabled ? "In der Slideshow" : "Nicht in der Slideshow")
        .accessibilityHint("Schaltet das Bild für die Slideshow an oder aus")
        .contextMenu {
            Button(isEnabled ? "Aus Slideshow entfernen" : "Zur Slideshow hinzufügen", action: onToggle)
            Button("Slideshow hier starten", action: onPlayFromHere)
            Divider()
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        .help(item.url.path)
        .task(id: item.url) {
            image = await loader.image(for: item.url, maxPixelSize: 320)
            // Liest nur den Container-Header, kostet also kaum etwas.
            frameCount = ImageLoader.frameCount(of: item.url)
        }
    }

    private var isAnimated: Bool { frameCount > 1 }

    private var tile: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))

                if let image {
                    // Das Bild liegt als Overlay auf einer leeren Fläche: so bestimmt die
                    // Kachel die Grösse und nicht umgekehrt. Direkt im ZStack würde ein
                    // Hochformat-Bild die Zelle auseinanderziehen und Nachbarn überlappen.
                    Color.clear
                        .overlay {
                            Image(decorative: image, scale: 1, orientation: .up)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView().controlSize(.small)
                }

                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isEnabled ? Color.accentColor : Color.clear, lineWidth: 2.5)
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isEnabled ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                if isAnimated {
                    Label("\(frameCount)", systemImage: "play.circle.fill")
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                        .help("Animiertes Bild mit \(frameCount) Einzelbildern")
                }
            }
            .opacity(isEnabled ? 1 : 0.45)

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isEnabled ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}
