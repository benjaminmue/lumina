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

            Button("Alle Bilder auswählen") { app.enableAll() }
                .disabled(app.items.isEmpty)
            Button("Auswahl aufheben") { app.disableAll() }
                .disabled(app.items.isEmpty)
        }
    }
}
