import AppKit
import SwiftUI

/// Reicht das NSWindow der Szene nach SwiftUI durch - nötig fürs Umschalten in den Vollbildmodus.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Beim Erzeugen hängt die View noch an keinem Fenster.
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}

extension NSWindow {
    var isFullscreen: Bool { styleMask.contains(.fullScreen) }
}
