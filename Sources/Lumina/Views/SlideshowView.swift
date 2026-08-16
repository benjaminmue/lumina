import AppKit
import CoreGraphics
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
    /// Kleine Vorschau des ersten Bildes, damit der Start nicht schwarz ist.
    @State private var posterImage: CGImage?

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
                } else {
                    loadingState
                }

                controlsOverlay
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
            .task {
                // Die Vorschau liegt aus dem Raster meist schon im Cache.
                if let first = items.first {
                    posterImage = await loader.image(for: first.url, maxPixelSize: 320)
                }
            }
        }
        .background(Color(white: config.backgroundBrightness))
        .background(WindowAccessor { playerWindow = $0 })
    }

    // MARK: - Zustände

    /// Statt Spinner auf Schwarz: das Bild unscharf vorab, wie es Fotos und TV machen.
    private var loadingState: some View {
        ZStack {
            if let posterImage {
                Image(decorative: posterImage, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 44, opaque: true)
                    .opacity(0.55)
                    .ignoresSafeArea()
            }

            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.8))
                Text("Wird geladen …")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var controlsOverlay: some View {
        // Gestapelt statt gestapelt-in-VStack: die Steuerung bringt ihren eigenen
        // Verlauf über die volle Breite mit, der Fortschrittsbalken liegt darüber.
        ZStack(alignment: .bottom) {
            if showControls || engine.didFinish {
                PlayerControls(
                    state: .init(
                        index: engine.currentIndex,
                        count: engine.count,
                        isPaused: engine.isPaused,
                        title: engine.slide?.item.name ?? "",
                        didFinish: engine.didFinish
                    ),
                    actions: .init(
                        previous: { engine.previous() },
                        togglePause: { engine.togglePause() },
                        next: { engine.next() },
                        restart: { engine.jump(to: 0) },
                        exit: onExit
                    ),
                    showsTitle: config.showFilename
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if config.showFilename, let slide = engine.slide {
                Text(slide.item.name)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(.bottom, 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }

            if config.showProgress {
                progressBar
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showControls)
        .animation(.easeOut(duration: 0.25), value: engine.didFinish)
    }

    /// Im Ruhezustand ein Haarstrich, bei sichtbarer Steuerung kräftiger.
    private var progressBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(engine.isPaused ? Color.accentColor : .white)
                .opacity(showControls ? 0.9 : 0.55)
                .frame(width: geo.size.width * engine.progress)
                .animation(.linear(duration: 0.05), value: engine.progress)
        }
        .frame(height: showControls ? 4 : 2)
        .background(.white.opacity(0.12))
        .animation(.easeOut(duration: 0.2), value: showControls)
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
