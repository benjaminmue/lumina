import AppKit
import Combine
import os
import LuminaCore
import SwiftUI

private let stateLog = Logger(subsystem: "ch.bebamu.lumina", category: "state")

/// Zentraler Zustand des Hauptfensters: geladene Bilder, Auswahl und Einstellungen.
@MainActor
final class AppState: ObservableObject {
    private enum Keys {
        static let config = "lumina.config"
        static let sources = "lumina.sources"
        static let preferences = "lumina.preferences"
    }

    @Published var config: SlideshowConfig {
        didSet { persistConfig() }
    }

    /// App-Einstellungen, getrennt von den Show-Parametern: eine Vorlage
    /// überschreibt `config` komplett und dürfte diese Werte nicht mitreissen.
    @Published var preferences: AppPreferences {
        didSet { persistPreferences() }
    }

    /// Alle importierten Bilder in Anzeigereihenfolge.
    @Published private(set) var items: [MediaItem] = []
    /// Bilder, die tatsächlich abgespielt werden.
    @Published private(set) var enabled: Set<URL> = []
    /// Im Raster markierte Bilder.
    ///
    /// Bewusst getrennt von `enabled`: auf dem Mac ist Markieren etwas anderes als
    /// Aktivieren. Markiert wird mit Klick, Cmd-Klick und Shift-Klick, die Aktion auf
    /// der Markierung erfolgt danach über Leertaste, Menü oder Kontextmenü.
    @Published private(set) var selection: Set<URL> = []
    /// Zeigt auch die aus der Slideshow entfernten Bilder an, damit man sie
    /// zurückholen kann. Normalerweise sind sie schlicht weg.
    @Published var showsRemoved = false

    /// Ausgangspunkt für die Bereichsauswahl mit Shift.
    private var selectionAnchor: URL?
    /// Zuletzt gewählte Dateien und Ordner - wird beim Start automatisch neu eingelesen.
    @Published private(set) var sources: [URL] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isPresenting = false
    /// Startposition der Slideshow, bezogen auf `playableItems`.
    @Published private(set) var presentIndex = 0
    @Published var errorMessage: LocalizedStringResource?
    /// Gefundene neuere Version. Wird in der Statuszeile dezent gemeldet.
    @Published var availableUpdate: ReleaseInfo?

    /// Vollbild-Bilder und Vorschaukacheln haben getrennte Caches, damit die
    /// vielen kleinen Thumbnails die grossen Bilder nicht aus dem Speicher drängen.
    let loader = ImageLoader(memoryLimitMB: 512)
    let thumbnailLoader = ImageLoader(memoryLimitMB: 96)

    private let defaults: UserDefaults
    /// Neuer Seed pro Import, damit Zufallssortierung bei jedem Import anders ausfällt.
    private var shuffleSeed: UInt64 = 0x5EED

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.config) {
            do {
                self.config = try JSONDecoder().decode(SlideshowConfig.self, from: data).sanitized()
            } catch {
                // Nicht stillschweigend zurücksetzen: sonst wundert man sich, warum
                // alle Einstellungen weg sind, und findet nie heraus warum.
                stateLog.error("Einstellungen unlesbar, Standardwerte aktiv: \(error.localizedDescription, privacy: .public)")
                self.config = SlideshowConfig()
            }
        } else {
            self.config = SlideshowConfig()
        }
        self.preferences = Self.loadPreferences(from: defaults)

        if let paths = defaults.array(forKey: Keys.sources) as? [String] {
            self.sources = paths.map { URL(fileURLWithPath: $0) }
        }
    }

    /// Liest die Einstellungen, ohne eine Instanz zu brauchen.
    static func loadPreferences(from defaults: UserDefaults = .standard) -> AppPreferences {
        guard let data = defaults.data(forKey: Keys.preferences) else { return AppPreferences() }
        do {
            return try JSONDecoder().decode(AppPreferences.self, from: data).sanitized()
        } catch {
            stateLog.error("Einstellungen unlesbar, Standardwerte aktiv: \(error.localizedDescription, privacy: .public)")
            return AppPreferences()
        }
    }

    var playableItems: [MediaItem] {
        items.filter { enabled.contains($0.url) }
    }

    /// Was das Raster zeigt: die Bilder der Slideshow.
    ///
    /// Entfernte Bilder erscheinen nur, wenn `showsRemoved` gesetzt ist - eine graue
    /// Kachel, die liegen bleibt, liest sich sonst wie ein Fehler statt wie "entfernt".
    var visibleItems: [MediaItem] {
        showsRemoved ? items : items.filter { enabled.contains($0.url) }
    }

    /// Wie viele Bilder aus der Slideshow genommen wurden.
    var removedCount: Int { items.count - enabled.count }

    var canPresent: Bool { !playableItems.isEmpty }

    var selectedItems: [MediaItem] {
        items.filter { selection.contains($0.url) }
    }

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

    /// Liest alle Quellen neu ein - etwa nach dem Umschalten von "Include subfolders".
    func reload() async {
        guard !sources.isEmpty else {
            items = []
            enabled = []
            return
        }
        isImporting = true
        defer { isImporting = false }

        let urls = sources
        let recursive = preferences.recursiveImport
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
            errorMessage = "No supported image files were found in that selection."
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

    // MARK: - Aktualisierung

    /// Sucht beim Start nach einer neueren Version, sofern eingeschaltet und fällig.
    ///
    /// Bewusst leise: gefunden wird höchstens ein Hinweis in der Statuszeile, kein Dialog.
    func checkForUpdatesIfDue() async {
        guard preferences.isUpdateCheckDue() else { return }

        let result = await UpdateChecker.latestRelease(owner: "benjaminmue", repo: "lumina")
        preferences.lastUpdateCheck = Date()

        guard case .success(let release) = result else { return }
        let installed = SemanticVersion(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        ) ?? SemanticVersion(major: 0, minor: 0, patch: 0)

        if preferences.shouldAnnounce(release.version, current: installed) {
            availableUpdate = release
        }
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

    // MARK: - Markierung

    func isSelected(_ item: MediaItem) -> Bool { selection.contains(item.url) }

    /// Klick auf eine Kachel.
    ///
    /// - Parameters:
    ///   - extend: Umschalt-Taste - Bereich vom Anker bis hierher.
    ///   - toggle: Befehlstaste - einzelnes Bild zur Markierung hinzu oder weg.
    func select(_ item: MediaItem, extend: Bool = false, toggle: Bool = false) {
        let list = visibleItems

        if extend, let anchor = selectionAnchor,
           let from = list.firstIndex(where: { $0.url == anchor }),
           let to = list.firstIndex(where: { $0.url == item.url }) {
            let range = from <= to ? from...to : to...from
            selection = Set(list[range].map(\.url))
            return
        }

        if toggle {
            if selection.contains(item.url) {
                selection.remove(item.url)
            } else {
                selection.insert(item.url)
            }
            selectionAnchor = item.url
            return
        }

        selection = [item.url]
        selectionAnchor = item.url
    }

    /// Verschiebt die Markierung mit den Pfeiltasten.
    func moveSelection(by offset: Int, extend: Bool = false) {
        let list = visibleItems
        guard !list.isEmpty else { return }

        let currentIndex = selectionAnchor.flatMap { anchor in
            list.firstIndex(where: { $0.url == anchor })
        } ?? -1
        let target = min(max(currentIndex + offset, 0), list.count - 1)
        select(list[target], extend: extend)
    }

    func selectAll() {
        selection = Set(visibleItems.map(\.url))
        selectionAnchor = visibleItems.first?.url
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
    }

    // MARK: - Zugehörigkeit zur Slideshow

    func isEnabled(_ item: MediaItem) -> Bool { enabled.contains(item.url) }

    func toggleInclusion(_ item: MediaItem) {
        if enabled.contains(item.url) {
            enabled.remove(item.url)
        } else {
            enabled.insert(item.url)
        }
    }

    /// Schaltet die markierten Bilder gesammelt um. Ist nichts markiert, passiert nichts.
    ///
    /// Enthält die Markierung sowohl aktive als auch inaktive Bilder, werden alle
    /// aktiviert - das ist die erwartbare Richtung.
    func toggleInclusionOfSelection() {
        let urls = selection
        guard !urls.isEmpty else { return }

        if urls.isSubset(of: enabled) {
            enabled.subtract(urls)
        } else {
            enabled.formUnion(urls)
        }
    }

    func setInclusion(_ included: Bool, for urls: Set<URL>) {
        if included {
            enabled.formUnion(urls)
        } else {
            enabled.subtract(urls)
        }
    }

    /// Nimmt die markierten Bilder aus der Slideshow. Die Dateien bleiben unangetastet.
    func removeSelected() {
        guard !selection.isEmpty else { return }
        enabled.subtract(selection)
        selection = []
        selectionAnchor = nil
    }

    /// Holt die markierten Bilder zurück.
    func restoreSelected() {
        guard !selection.isEmpty else { return }
        enabled.formUnion(selection)
    }

    func enableAll() { enabled = Set(items.map(\.url)) }
    func disableAll() { enabled = [] }

    /// Behält nur die markierten Bilder in der Slideshow.
    func keepOnlySelected() {
        guard !selection.isEmpty else { return }
        enabled = selection
    }

    // MARK: - Persistenz

    private func persistPreferences() {
        do {
            defaults.set(try JSONEncoder().encode(preferences), forKey: Keys.preferences)
        } catch {
            stateLog.error("Einstellungen nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistConfig() {
        do {
            defaults.set(try JSONEncoder().encode(config), forKey: Keys.config)
        } catch {
            stateLog.error("Einstellungen nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }
}
