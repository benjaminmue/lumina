import AppKit
import LuminaCore
import SwiftUI

/// Der Player: zeigt die Bilder, reagiert auf Tastatur und blendet die Steuerung ein.
struct SlideshowView: View {
    let items: [MediaItem]
    let config: SlideshowConfig
    let loader: ImageLoader
    let onExit: () -> Void

    @StateObject private var engine: SlideshowEngine
    @State private var showControls = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    @State private var playerWindow: NSWindow?

    init(
        items: [MediaItem],
        config: SlideshowConfig,
        loader: ImageLoader,
        startIndex: Int = 0,
        onExit: @escaping () -> Void
    ) {
        self.items = items
        self.config = config
        self.loader = loader
        self.onExit = onExit
        _engine = StateObject(
            wrappedValue: SlideshowEngine(
                items: items,
                config: config,
                loader: loader,
                startIndex: startIndex
            )
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(white: config.backgroundBrightness)
                    .ignoresSafeArea()

                if let slide = engine.slide {
                    SlideLayerView(
                        slide: slide,
                        config: config,
                        isPaused: engine.isPaused,
                        maxPixelSize: engine.targetPixelSize
                    )
                        .id(slide.id)
                        .transition(
                            SlideTransitions.transition(
                                for: slide.transition,
                                direction: slide.direction,
                                duration: config.transitionDuration
                            )
                        )
                        .zIndex(Double(slide.id))
                } else if engine.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }

                if engine.didFinish {
                    endOverlay
                        .zIndex(10_000)
                }

                controlsOverlay(width: geo.size.width)
                    .zIndex(20_000)
            }
            .clipped()
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active = phase { revealControls() }
            }
            .onTapGesture { engine.togglePause() }
            .onAppear {
                Task { await applyTargetPixelSize(for: geo.size) }
                engine.start()
                installKeyMonitor()
                NSCursor.setHiddenUntilMouseMoves(true)
            }
            // Der Wechsel ins Vollbild passiert erst nach onAppear: ohne diese Kopplung
            // liefe die ganze Slideshow mit der Auflösung des kleinen Fensters.
            .onChange(of: geo.size) { _, newSize in
                Task { await applyTargetPixelSize(for: newSize) }
            }
            .onDisappear {
                engine.stop()
                hideControlsTask?.cancel()
                removeKeyMonitor()
                NSCursor.unhide()
            }
            .onChange(of: config) { _, newValue in
                engine.update(config: newValue)
            }
        }
        .background(Color(white: config.backgroundBrightness))
        .background(WindowAccessor { playerWindow = $0 })
    }

    // MARK: - Overlays

    private var endOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .light))
            Text("Slideshow beendet")
                .font(.title3)
            HStack(spacing: 12) {
                Button("Von vorne") { engine.jump(to: 0) }
                Button("Schliessen") { onExit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func controlsOverlay(width: CGFloat) -> some View {
        VStack {
            Spacer()

            if config.showFilename, let slide = engine.slide, !showControls {
                Text(slide.item.name)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, config.showProgress ? 14 : 24)
                    .transition(.opacity)
            }

            if showControls {
                controlBar
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if config.showProgress {
                GeometryReader { geo in
                    Rectangle()
                        .fill(.white.opacity(0.75))
                        .frame(width: geo.size.width * engine.progress)
                        .animation(.linear(duration: 0.05), value: engine.progress)
                }
                .frame(height: 3)
                .background(.white.opacity(0.15))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    private var controlBar: some View {
        HStack(spacing: 18) {
            Button {
                engine.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .help("Vorheriges Bild (Pfeil links)")

            Button {
                engine.togglePause()
            } label: {
                Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 22)
            }
            .help("Pause / Weiter (Leertaste)")

            Button {
                engine.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .help("Nächstes Bild (Pfeil rechts)")

            Divider().frame(height: 18)

            Text("\(engine.currentIndex + 1) / \(engine.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            if let slide = engine.slide {
                Text(slide.item.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320, alignment: .leading)
            }

            Divider().frame(height: 18)

            Button {
                onExit()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Slideshow beenden (Esc)")
        }
        .buttonStyle(.borderless)
        .font(.title3)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 18, y: 6)
    }

    // MARK: - Eingabe

    /// Rechnet die Anzeigefläche in eine Dekodier-Auflösung um, inklusive Reserve
    /// für Retina-Skalierung und den Ken-Burns-Zoom.
    private func applyTargetPixelSize(for size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }
        let scaleFactor = playerWindow?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let longestEdge = max(size.width, size.height) * scaleFactor * 1.3
        await engine.setTargetPixelSize(Int(min(max(longestEdge, 1280), 6000)))
    }

    private func revealControls() {
        showControls = true
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            showControls = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    /// Tastatur wird über einen lokalen Event-Monitor abgefangen statt über `onKeyPress`,
    /// weil der Player im Vollbild sonst je nach Fokus keine Tastendrücke sieht.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Der Monitor gilt appweit. Ohne diese Prüfung würde er Tastendrücke auch
            // in Dialogen und anderen Fenstern der App verschlucken.
            guard let target = playerWindow, event.window === target else { return event }

            switch event.keyCode {
            case 49: // Leertaste
                engine.togglePause()
                revealControls()
                return nil
            case 123, 126: // Pfeil links, Pfeil hoch
                engine.previous()
                revealControls()
                return nil
            case 124, 125, 36: // Pfeil rechts, Pfeil runter, Return
                engine.next()
                revealControls()
                return nil
            case 53: // Escape
                onExit()
                return nil
            case 115: // Pos1
                engine.jump(to: 0)
                return nil
            case 119: // Ende
                engine.jump(to: max(items.count - 1, 0))
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}
