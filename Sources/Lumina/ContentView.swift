import AppKit
import LuminaCore
import SwiftUI

/// Wurzelansicht: schaltet zwischen Bibliothek und Player um und steuert den Vollbildmodus.
struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @State private var window: NSWindow?
    /// Nur ein selbst ausgelöster Vollbildwechsel wird beim Beenden zurückgenommen -
    /// wer das Fenster vorher schon selbst auf Vollbild gestellt hat, behält es.
    @State private var didEnterFullscreen = false
    /// Merkt einen Vollbildwunsch, solange die Fensterreferenz noch fehlt.
    @State private var wantsFullscreen = false

    var body: some View {
        ZStack {
            if app.isPresenting {
                SlideshowView(
                    items: app.playableItems,
                    config: app.config,
                    loader: app.loader,
                    startIndex: app.presentIndex,
                    onExit: app.stopPresenting
                )
                .transition(.opacity)
            } else {
                LibraryView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.isPresenting)
        .background(
            WindowAccessor { newWindow in
                window = newWindow
                // Wer direkt nach dem Start ⌘R drückt, ist schneller als die
                // Fensterreferenz - der Wunsch wird hier nachgeholt.
                if wantsFullscreen { enterFullscreenIfWanted() }
            }
        )
        // Deckt jeden Weg ab: Escape im Player, Menüeintrag oder Ende der Slideshow.
        .onChange(of: app.isPresenting) { _, presenting in
            if presenting {
                enterFullscreenIfWanted()
            } else {
                leaveFullscreenIfNeeded()
            }
        }
    }

    private func enterFullscreenIfWanted() {
        guard app.config.startFullscreen else {
            wantsFullscreen = false
            return
        }
        guard let window else {
            wantsFullscreen = true
            return
        }
        wantsFullscreen = false
        guard !window.isFullscreen else { return }
        window.toggleFullScreen(nil)
        didEnterFullscreen = true
    }

    private func leaveFullscreenIfNeeded() {
        wantsFullscreen = false
        if didEnterFullscreen, let window, window.isFullscreen {
            window.toggleFullScreen(nil)
        }
        didEnterFullscreen = false
    }
}
