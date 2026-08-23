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
                    if app.preferences.restoreSession {
                        await app.reload()
                    }
                    await app.checkForUpdatesIfDue()
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands { LuminaCommands(app: app) }

        // Eigene Szene: bringt den Menüeintrag "Einstellungen …" und Cmd-Komma mit.
        Settings {
            SettingsWindow()
                .environmentObject(app)
                // Eigene Szene: sie erbt die Locale des Hauptfensters nicht.
                // Ohne diese Zeile zeigt das Fenster die Sprache aus AppleLanguages
                // und hinkt damit der gerade getroffenen Wahl hinterher.
                .environment(\.locale, app.preferences.effectiveLanguage().locale)
        }
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
            Button("Choose images …") {
                Task { await app.addSources(FilePicker.chooseImages()) }
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Choose folders …") {
                Task { await app.addSources(FilePicker.chooseFolders()) }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Clear list") { app.clear() }
                .disabled(app.items.isEmpty)
        }

        CommandMenu("Slideshow") {
            Button("Start") { app.present() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!app.canPresent || app.isPresenting)

            // Ohne Tastenkürzel: Escape fängt der Player selbst ab, ein Menü-Shortcut
            // würde ihm die Taste wegnehmen.
            Button("Stop") { app.stopPresenting() }
                .disabled(!app.isPresenting)

            Divider()

            // Kein Tastenkürzel: die Leertaste hängt am Raster selbst, als Menükürzel
            // würde sie auch im Suchfeld und im Player abgefangen.
            // Während der Wiedergabe gesperrt: die Engine arbeitet mit einer Kopie
            // der Liste, Änderungen wirkten erst beim nächsten Start.
            Button("Remove marked") { app.removeSelected() }
                .disabled(app.selection.isEmpty || app.isPresenting)
            Button("Remove all") { app.disableAll() }
                .disabled(app.items.isEmpty || app.isPresenting)
            Button("Restore all") { app.enableAll() }
                .disabled(app.removedCount == 0 || app.isPresenting)
        }

        CommandGroup(after: .pasteboard) {
            Button("Mark all") { app.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(app.items.isEmpty)
            Button("Clear marks") { app.clearSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(app.selection.isEmpty)
        }
    }
}
