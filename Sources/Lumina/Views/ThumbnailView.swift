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

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))

                if let image {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView().controlSize(.small)
                }

                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isEnabled ? Color.accentColor : Color.clear, lineWidth: 2.5)
            }
            .frame(height: 120)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isEnabled ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(6)
            }
            .opacity(isEnabled ? 1 : 0.45)

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isEnabled ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
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
        }
    }
}
