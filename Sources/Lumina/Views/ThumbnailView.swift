import AppKit
import CoreGraphics
import LuminaCore
import SwiftUI

/// Vorschaukachel im Hauptfenster.
///
/// Markieren und Zugehörigkeit zur Slideshow sind zwei getrennte Dinge: ein Klick
/// markiert (wie im Finder, mit Cmd und Shift), das Häkchen oben rechts nimmt das
/// Bild in die Show oder heraus, ein Doppelklick startet ab hier.
struct ThumbnailView: View {
    let item: MediaItem
    let loader: ImageLoader
    let isEnabled: Bool
    let isSelected: Bool
    let onSelect: (_ extend: Bool, _ toggle: Bool) -> Void
    let onToggleInclusion: () -> Void
    let onPlayFromHere: () -> Void

    @State private var image: CGImage?
    @State private var frameCount = 1
    @State private var isHovered = false

    private let corner: CGFloat = 10

    init(
        item: MediaItem,
        loader: ImageLoader,
        isEnabled: Bool,
        isSelected: Bool,
        onSelect: @escaping (Bool, Bool) -> Void,
        onToggleInclusion: @escaping () -> Void,
        onPlayFromHere: @escaping () -> Void
    ) {
        self.item = item
        self.loader = loader
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onToggleInclusion = onToggleInclusion
        self.onPlayFromHere = onPlayFromHere
        // Bereits geladene Vorschau sofort setzen, sonst blitzt die Kachel beim
        // Scrollen leer auf, bevor die Aufgabe unten greift.
        _image = State(initialValue: loader.cachedImage(for: item.url, maxPixelSize: 320))
    }

    var body: some View {
        tile
            .onHover { isHovered = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.name)
            .accessibilityValue(isEnabled ? "In the slideshow" : "Not in the slideshow")
            .contextMenu { contextMenu }
            .help(item.url.path)
            .task(id: item.url) {
                if image == nil {
                    image = await loader.image(for: item.url, maxPixelSize: 320)
                }
                frameCount = await loader.animationInfo(for: item.url)?.frameCount ?? 1
            }
    }

    private var isAnimated: Bool { frameCount > 1 }

    // MARK: - Kachel

    private var tile: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(.quaternary)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner))
            // Nicht enthaltene Bilder werden entsättigt und gedimmt: das liest sich
            // sofort, ohne dass ein Rahmen um jede Kachel nötig wäre.
            .saturation(isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            // Die Auswahl-Geste liegt bewusst hier und nicht um die ganze Kachel:
            // sonst verschliesst ihre Trefferfläche die Knöpfe in den Overlays.
            .contentShape(RoundedRectangle(cornerRadius: corner))
            .onTapGesture(count: 2, perform: onPlayFromHere)
            .onTapGesture {
                // SwiftUI reicht bei Tap-Gesten keine Modifiertasten durch.
                let flags = NSEvent.modifierFlags
                onSelect(flags.contains(.shift), flags.contains(.command))
            }
            .overlay(alignment: .bottom) { hoverFooter }
            .overlay(alignment: .topLeading) { animationBadge }
            .overlay(alignment: .topTrailing) { inclusionToggle }
            .overlay {
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
            }
            .scaleEffect(isHovered ? 1.015 : 1)
            .animation(.snappy(duration: 0.14), value: isHovered)
            .animation(.snappy(duration: 0.14), value: isSelected)
            .animation(.snappy(duration: 0.2), value: isEnabled)
    }

    @ViewBuilder
    private var hoverFooter: some View {
        if isHovered {
            ZStack(alignment: .bottomTrailing) {
                // Verlauf und Dateiname sind reine Anzeige - ohne dieses
                // allowsHitTesting würden sie Klicks auf die Kachel abfangen.
                HStack {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.white)
                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 8)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)

                Button(action: onPlayFromHere) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Start slideshow here")
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var animationBadge: some View {
        if isAnimated {
            Label(isHovered ? "\(frameCount)" : "", systemImage: "play.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())
                .padding(6)
                .help("Animated image with \(frameCount) frames")
                .allowsHitTesting(false)
        }
    }

    /// Kreuz zum Entfernen, Plus zum Zurückholen.
    ///
    /// Ein Häkchen stand hier vorher und wurde als "deaktiviert" gelesen statt als
    /// "aus der Slideshow genommen" - das Symbol muss die Aktion zeigen, nicht den Zustand.
    @ViewBuilder
    private var inclusionToggle: some View {
        if !isEnabled || isHovered || isSelected {
            Button(action: onToggleInclusion) {
                Image(systemName: isEnabled ? "xmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isEnabled ? .black.opacity(0.55) : Color.accentColor)
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
            .buttonStyle(.plain)
            .padding(6)
            .help(isEnabled ? "Remove from slideshow" : "Add back")
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(isEnabled ? "Remove" : "Add back", action: onToggleInclusion)
        Button("Start slideshow here", action: onPlayFromHere)
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
        Button("Copy path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.path, forType: .string)
        }
    }
}
