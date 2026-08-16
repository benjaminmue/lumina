import AppKit
import Combine
import LuminaCore
import SwiftUI

/// Zentraler Zustand des Hauptfensters: geladene Bilder, Auswahl und Einstellungen.
@MainActor
final class AppState: ObservableObject {
    private enum Keys {
        static let config = "lumina.config"
        static let sources = "lumina.sources"
    }

    @Published var config: SlideshowConfig {
        didSet { persistConfig() }
    }

    /// Alle importierten Bilder in Anzeigereihenfolge.
    @Published private(set) var items: [MediaItem] = []
    /// Bilder, die tatsächlich abgespielt werden. Erlaubt das Abwählen einzelner Bilder
    /// aus einem importierten Ordner.
    @Published private(set) var enabled: Set<URL> = []
    /// Zuletzt gewählte Dateien und Ordner - wird beim Start automatisch neu eingelesen.
    @Published private(set) var sources: [URL] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isPresenting = false
    /// Startposition der Slideshow, bezogen auf `playableItems`.
    @Published private(set) var presentIndex = 0
    @Published var errorMessage: String?

    /// Vollbild-Bilder und Vorschaukacheln haben getrennte Caches, damit die
    /// vielen kleinen Thumbnails die grossen Bilder nicht aus dem Speicher drängen.
    let loader = ImageLoader(memoryLimitMB: 512)
    let thumbnailLoader = ImageLoader(memoryLimitMB: 96)

    private let defaults: UserDefaults
    /// Neuer Seed pro Import, damit Zufallssortierung bei jedem Import anders ausfällt.
    private var shuffleSeed: UInt64 = 0x5EED

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.config),
           let decoded = try? JSONDecoder().decode(SlideshowConfig.self, from: data) {
            self.config = decoded.sanitized()
        } else {
            self.config = SlideshowConfig()
        }
        if let paths = defaults.array(forKey: Keys.sources) as? [String] {
            self.sources = paths.map { URL(fileURLWithPath: $0) }
        }
    }

    var playableItems: [MediaItem] {
        items.filter { enabled.contains($0.url) }
    }

    var canPresent: Bool { !playableItems.isEmpty }

    // MARK: - Import

    /// Ersetzt die aktuelle Bildliste durch die Inhalte der übergebenen URLs.
    func replaceSources(with urls: [URL]) async {
        sources = urls
        defaults.set(urls.map(\.path), forKey: Keys.sources)
        shuffleSeed = UInt64.random(in: 1...UInt64.max)
        await reload()
    }

    /// Hängt weitere Dateien oder Ordner an die bestehende Auswahl an.
    func addSources(_ urls: [URL]) async {
        let merged = sources + urls.filter { !sources.contains($0) }
        await replaceSources(with: merged)
    }

    /// Liest alle Quellen neu ein - etwa nach dem Umschalten von "Unterordner einbeziehen".
    func reload() async {
        guard !sources.isEmpty else {
            items = []
            enabled = []
            return
        }
        isImporting = true
        defer { isImporting = false }

        let urls = sources
        let recursive = config.recursiveImport
        let order = config.sortOrder
        let ascending = config.ascending
        let seed = shuffleSeed

        let found: [MediaItem] = await Task.detached(priority: .userInitiated) {
            let collected = MediaScanner.collect(from: urls, recursive: recursive)
            return MediaScanner.sort(collected, by: order, ascending: ascending, seed: seed)
        }.value

        // Bereits abgewählte Bilder bleiben abgewählt, neue kommen aktiviert dazu.
        let previouslyKnown = Set(items.map(\.url))
        let stillEnabled = enabled.intersection(found.map(\.url))
        let freshlyAdded = found.map(\.url).filter { !previouslyKnown.contains($0) }

        items = found
        enabled = stillEnabled.union(freshlyAdded)

        if found.isEmpty {
            errorMessage = "In der Auswahl wurden keine unterstützten Bilddateien gefunden."
        }
    }

    /// Sortiert die vorhandene Liste neu, ohne die Platte erneut zu durchsuchen.
    func resort() {
        items = MediaScanner.sort(items, by: config.sortOrder, ascending: config.ascending, seed: shuffleSeed)
    }

    /// Zieht einen neuen Zufalls-Seed und mischt die Liste neu.
    func reshuffle() {
        shuffleSeed = UInt64.random(in: 1...UInt64.max)
        resort()
    }

    func clear() {
        sources = []
        items = []
        enabled = []
        defaults.removeObject(forKey: Keys.sources)
        Task { await loader.clearCache() }
    }

    // MARK: - Wiedergabe

    /// Startet die Slideshow beim ersten ausgewählten Bild.
    func present() {
        guard canPresent else { return }
        presentIndex = 0
        isPresenting = true
    }

    /// Startet die Slideshow bei einem bestimmten Bild. Ist dieses Bild abgewählt,
    /// wird es für den Start automatisch aktiviert.
    func present(startingAt item: MediaItem) {
        if !enabled.contains(item.url) { enabled.insert(item.url) }
        guard let index = playableItems.firstIndex(where: { $0.url == item.url }) else { return }
        presentIndex = index
        isPresenting = true
    }

    func stopPresenting() {
        isPresenting = false
    }

    // MARK: - Auswahl

    func isEnabled(_ item: MediaItem) -> Bool { enabled.contains(item.url) }

    func toggle(_ item: MediaItem) {
        if enabled.contains(item.url) {
            enabled.remove(item.url)
        } else {
            enabled.insert(item.url)
        }
    }

    func enableAll() { enabled = Set(items.map(\.url)) }
    func disableAll() { enabled = [] }
    func invertSelection() { enabled = Set(items.map(\.url)).subtracting(enabled) }

    // MARK: - Persistenz

    private func persistConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Keys.config)
    }
}
