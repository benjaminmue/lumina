import Foundation

/// Einstellungen, die zur App gehören und nicht zu einer einzelnen Slideshow.
///
/// Die Trennung von `SlideshowConfig` hat einen handfesten Grund: eine Vorlage
/// ("Bildschirmschoner", "Präsentation") überschreibt die Show-Parameter komplett.
/// Läge hier etwas mit, würde ein Klick auf eine Vorlage stillschweigend globale
/// Einstellungen mitverändern.
public struct AppPreferences: Codable, Equatable, Sendable {
    /// Gewählte Oberflächensprache. `nil` bedeutet: der Systemsprache folgen.
    public var language: AppLanguage?
    /// Ob die Sprachfrage beim ersten Start schon beantwortet wurde.
    public var didAskForLanguage: Bool

    /// Zuletzt genutzte Quellen beim Start wieder einlesen.
    public var restoreSession: Bool
    /// Unterordner beim Ordner-Import mitlesen.
    public var recursiveImport: Bool
    /// Vor dem Leeren der Liste nachfragen.
    public var confirmClear: Bool

    /// Slideshow im Vollbild starten.
    public var startFullscreen: Bool
    /// Animierte Bilder mindestens einmal ganz abspielen.
    public var playAnimationsFully: Bool
    /// Ruhezustand und Bildschirmschoner während der Wiedergabe unterdrücken.
    public var preventSleep: Bool
    /// Nach wie vielen Sekunden ohne Mausbewegung der Zeiger verschwindet.
    public var cursorHideDelay: Double

    /// Beim Start nach einer neuen Version suchen, höchstens einmal pro Woche.
    public var checkForUpdates: Bool
    /// Zeitpunkt der letzten Suche.
    public var lastUpdateCheck: Date?
    /// Version, die der Benutzer übersprungen hat. Erst die nächste meldet sich wieder.
    public var skippedVersion: String?

    public static let cursorDelayRange: ClosedRange<Double> = 1...10

    public init(
        language: AppLanguage? = nil,
        didAskForLanguage: Bool = false,
        restoreSession: Bool = true,
        recursiveImport: Bool = true,
        confirmClear: Bool = true,
        startFullscreen: Bool = true,
        playAnimationsFully: Bool = true,
        preventSleep: Bool = true,
        cursorHideDelay: Double = 2.5,
        checkForUpdates: Bool = true,
        lastUpdateCheck: Date? = nil,
        skippedVersion: String? = nil
    ) {
        self.language = language
        self.didAskForLanguage = didAskForLanguage
        self.restoreSession = restoreSession
        self.recursiveImport = recursiveImport
        self.confirmClear = confirmClear
        self.startFullscreen = startFullscreen
        self.playAnimationsFully = playAnimationsFully
        self.preventSleep = preventSleep
        self.cursorHideDelay = cursorHideDelay
        self.checkForUpdates = checkForUpdates
        self.lastUpdateCheck = lastUpdateCheck
        self.skippedVersion = skippedVersion
    }

    /// Fehlende Felder fallen auf ihren Standardwert zurück, damit eine ältere
    /// gespeicherte Datei nicht die ganzen Einstellungen zurücksetzt.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppPreferences()

        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language)
        didAskForLanguage = try container.decodeIfPresent(Bool.self, forKey: .didAskForLanguage) ?? fallback.didAskForLanguage
        restoreSession = try container.decodeIfPresent(Bool.self, forKey: .restoreSession) ?? fallback.restoreSession
        recursiveImport = try container.decodeIfPresent(Bool.self, forKey: .recursiveImport) ?? fallback.recursiveImport
        confirmClear = try container.decodeIfPresent(Bool.self, forKey: .confirmClear) ?? fallback.confirmClear
        startFullscreen = try container.decodeIfPresent(Bool.self, forKey: .startFullscreen) ?? fallback.startFullscreen
        playAnimationsFully = try container.decodeIfPresent(Bool.self, forKey: .playAnimationsFully) ?? fallback.playAnimationsFully
        preventSleep = try container.decodeIfPresent(Bool.self, forKey: .preventSleep) ?? fallback.preventSleep
        cursorHideDelay = try container.decodeIfPresent(Double.self, forKey: .cursorHideDelay) ?? fallback.cursorHideDelay
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? fallback.checkForUpdates
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        skippedVersion = try container.decodeIfPresent(String.self, forKey: .skippedVersion)
    }

    public func sanitized() -> AppPreferences {
        var copy = self
        copy.cursorHideDelay = min(max(cursorHideDelay, Self.cursorDelayRange.lowerBound),
                                   Self.cursorDelayRange.upperBound)
        return copy
    }

    /// Ob eine automatische Suche fällig ist.
    ///
    /// - Parameter now: Bezugszeitpunkt, für Tests überschreibbar.
    public func isUpdateCheckDue(now: Date = Date(), interval: TimeInterval = 7 * 24 * 3600) -> Bool {
        guard checkForUpdates else { return false }
        guard let last = lastUpdateCheck else { return true }
        // Eine Uhr, die zurückgestellt wurde, darf die Suche nicht dauerhaft blockieren.
        if last > now { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// Die Sprache, in der die Oberfläche erscheinen soll.
    ///
    /// Ohne eigene Wahl folgt sie dem System; kennt das System keine der
    /// unterstützten Sprachen, bleibt es bei Englisch.
    public func effectiveLanguage(systemPreferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        language ?? AppLanguage.fromSystem(preferred: systemPreferred) ?? .english
    }

    /// Ob beim Start nach der Sprache gefragt werden muss.
    ///
    /// Nur dann, wenn das System keine der vorhandenen Sprachen verlangt und die
    /// Frage noch nie gestellt wurde. Wer Deutsch oder Japanisch eingestellt hat,
    /// bekommt die App wortlos in seiner Sprache.
    public func needsLanguagePrompt(systemPreferred: [String] = Locale.preferredLanguages) -> Bool {
        guard !didAskForLanguage, language == nil else { return false }
        return AppLanguage.fromSystem(preferred: systemPreferred) == nil
    }

    /// Ob eine gefundene Version gemeldet werden soll.
    public func shouldAnnounce(_ version: SemanticVersion, current: SemanticVersion) -> Bool {
        guard version > current else { return false }
        guard let skipped = skippedVersion.flatMap(SemanticVersion.init) else { return true }
        return version > skipped
    }
}
