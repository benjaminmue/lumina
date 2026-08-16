import AppKit
import SwiftUI

@main
struct LuminaApp: App {
    @StateObject private var app = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Lumina") {
            ContentView()
                .environmentObject(app)
                .task {
                    // Die zuletzt genutzten Ordner beim Start wieder einlesen.
                    await app.reload()
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands { LuminaCommands(app: app) }
    }
}

/// Beendet die App mit dem letzten Fenster - ein Fensterloser Zustand hat hier keinen Nutzen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Menüeinträge im Hauptmenü.
struct LuminaCommands: Commands {
    @ObservedObject var app: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Bilder wählen …") {
                Task { await app.addSources(FilePicker.chooseImages()) }
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Ordner wählen …") {
                Task { await app.addSources(FilePicker.chooseFolders()) }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Liste leeren") { app.clear() }
                .disabled(app.items.isEmpty)
        }

        CommandMenu("Slideshow") {
            Button("Starten") { app.present() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!app.canPresent || app.isPresenting)

            // Ohne Tastenkürzel: Escape fängt der Player selbst ab, ein Menü-Shortcut
            // würde ihm die Taste wegnehmen.
            Button("Beenden") { app.stopPresenting() }
                .disabled(!app.isPresenting)

            Divider()

            // Kein Tastenkürzel: die Leertaste hängt am Raster selbst, als Menükürzel
            // würde sie auch im Suchfeld und im Player abgefangen.
            // Während der Wiedergabe gesperrt: die Engine arbeitet mit einer Kopie
            // der Liste, Änderungen wirkten erst beim nächsten Start.
            Button("Markierte entfernen") { app.removeSelected() }
                .disabled(app.selection.isEmpty || app.isPresenting)
            Button("Alle entfernen") { app.disableAll() }
                .disabled(app.items.isEmpty || app.isPresenting)
            Button("Alle zurückholen") { app.enableAll() }
                .disabled(app.removedCount == 0 || app.isPresenting)
        }

        CommandGroup(after: .pasteboard) {
            Button("Alle markieren") { app.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(app.items.isEmpty)
            Button("Markierung aufheben") { app.clearSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(app.selection.isEmpty)
        }
    }
}
