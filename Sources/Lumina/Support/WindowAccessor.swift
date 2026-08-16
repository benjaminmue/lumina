import AppKit
import SwiftUI

/// Reicht das NSWindow der Szene nach SwiftUI durch - nötig fürs Umschalten in den Vollbildmodus.
///
/// Gemeldet wird nur, wenn sich das Fenster tatsächlich ändert. Die Aufrufer schreiben
/// im Callback in `@State`, was die View invalidiert; ohne diese Bremse triebe jede
/// Invalidierung den nächsten Aufruf und damit einen Dauerlauf über den Runloop.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    final class Coordinator {
        weak var lastWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Beim Erzeugen hängt die View noch an keinem Fenster.
        Task { @MainActor in
            guard let window = nsView.window, window !== context.coordinator.lastWindow else { return }
            context.coordinator.lastWindow = window
            onWindow(window)
        }
    }
}

extension NSWindow {
    var isFullscreen: Bool { styleMask.contains(.fullScreen) }
}
