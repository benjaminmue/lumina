import Foundation

/// Übergangseffekt zwischen zwei Bildern.
public enum TransitionStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case cut
    case crossfade
    case slide
    case push
    case zoomBlur
    case wipe
    case flip
    case random

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cut: return "Harter Schnitt"
        case .crossfade: return "Überblenden"
        case .slide: return "Schieben"
        case .push: return "Verdrängen"
        case .zoomBlur: return "Zoom"
        case .wipe: return "Wischen"
        case .flip: return "Umschlagen"
        case .random: return "Zufällig"
        }
    }

    /// Alle Stile, die als konkrete Auflösung von `.random` in Frage kommen.
    public static var concreteStyles: [TransitionStyle] {
        allCases.filter { $0 != .random && $0 != .cut }
    }

    /// Löst `.random` deterministisch anhand eines Seeds auf; alle anderen Werte bleiben unverändert.
    public func resolved(seed: UInt64) -> TransitionStyle {
        guard self == .random else { return self }
        var rng = SeededGenerator(seed: seed)
        return TransitionStyle.concreteStyles.randomElement(using: &rng) ?? .crossfade
    }
}

/// Wie ein Bild in die Anzeigefläche eingepasst wird.
public enum ScaleMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Ganzes Bild sichtbar, Ränder bleiben leer.
    case fit
    /// Fläche komplett gefüllt, Bild wird beschnitten.
    case fill
    /// Ganzes Bild sichtbar, Ränder mit unscharfer Bildkopie gefüllt.
    case fitBlurred

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fit: return "Einpassen"
        case .fill: return "Ausfüllen (Crop)"
        case .fitBlurred: return "Einpassen mit Unschärfe-Rand"
        }
    }
}

/// Stärke des Ken-Burns-Effekts (langsamer Zoom- und Schwenk-Effekt während der Standzeit).
public enum KenBurnsIntensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case subtle
    case medium
    case strong

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: return "Aus"
        case .subtle: return "Dezent"
        case .medium: return "Mittel"
        case .strong: return "Stark"
        }
    }

    /// Maximaler zusätzlicher Zoom-Faktor über die Standzeit.
    public var zoomRange: ClosedRange<Double> {
        switch self {
        case .off: return 1.0...1.0
        case .subtle: return 1.0...1.06
        case .medium: return 1.0...1.14
        case .strong: return 1.0...1.28
        }
    }

    /// Maximaler Schwenk als Anteil der Bildkante.
    public var panAmount: Double {
        switch self {
        case .off: return 0
        case .subtle: return 0.02
        case .medium: return 0.05
        case .strong: return 0.10
        }
    }
}

/// Sortierung der Bildliste.
public enum SortOrder: String, CaseIterable, Codable, Identifiable, Sendable {
    case name
    case dateCreated
    case dateModified
    case fileSize
    case shuffled

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .name: return "Dateiname"
        case .dateCreated: return "Erstelldatum"
        case .dateModified: return "Änderungsdatum"
        case .fileSize: return "Dateigrösse"
        case .shuffled: return "Zufall"
        }
    }
}

/// Alle persistierten Einstellungen einer Slideshow.
public struct SlideshowConfig: Codable, Equatable, Sendable {
    /// Standzeit pro Bild in Sekunden.
    public var slideDuration: Double
    /// Dauer des Übergangs in Sekunden.
    public var transitionDuration: Double
    public var transition: TransitionStyle
    public var scaleMode: ScaleMode
    public var kenBurns: KenBurnsIntensity
    public var sortOrder: SortOrder
    public var ascending: Bool
    /// Unterordner beim Ordner-Import mitlesen.
    public var recursiveImport: Bool
    /// Nach dem letzten Bild wieder von vorne beginnen.
    public var loop: Bool
    /// Slideshow im Vollbild starten.
    public var startFullscreen: Bool
    /// Dateiname unten einblenden.
    public var showFilename: Bool
    /// Fortschrittsbalken einblenden.
    public var showProgress: Bool
    /// Hintergrundhelligkeit hinter dem Bild (0 = schwarz, 1 = weiss).
    public var backgroundBrightness: Double

    public static let durationRange: ClosedRange<Double> = 1...120
    public static let transitionRange: ClosedRange<Double> = 0...5

    public init(
        slideDuration: Double = 5,
        transitionDuration: Double = 1.0,
        transition: TransitionStyle = .crossfade,
        scaleMode: ScaleMode = .fit,
        kenBurns: KenBurnsIntensity = .subtle,
        sortOrder: SortOrder = .name,
        ascending: Bool = true,
        recursiveImport: Bool = true,
        loop: Bool = true,
        startFullscreen: Bool = true,
        showFilename: Bool = false,
        showProgress: Bool = true,
        backgroundBrightness: Double = 0
    ) {
        self.slideDuration = slideDuration
        self.transitionDuration = transitionDuration
        self.transition = transition
        self.scaleMode = scaleMode
        self.kenBurns = kenBurns
        self.sortOrder = sortOrder
        self.ascending = ascending
        self.recursiveImport = recursiveImport
        self.loop = loop
        self.startFullscreen = startFullscreen
        self.showFilename = showFilename
        self.showProgress = showProgress
        self.backgroundBrightness = backgroundBrightness
    }

    /// Begrenzt alle Werte auf gültige Bereiche. Wird nach dem Laden aus UserDefaults angewendet,
    /// damit manipulierte oder veraltete Werte die Slideshow nicht blockieren.
    public func sanitized() -> SlideshowConfig {
        var copy = self
        copy.slideDuration = min(max(slideDuration, Self.durationRange.lowerBound), Self.durationRange.upperBound)
        copy.transitionDuration = min(max(transitionDuration, Self.transitionRange.lowerBound), Self.transitionRange.upperBound)
        // Der Übergang darf die Standzeit nicht auffressen, sonst steht das Bild nie still.
        copy.transitionDuration = min(copy.transitionDuration, copy.slideDuration * 0.8)
        copy.backgroundBrightness = min(max(backgroundBrightness, 0), 1)
        return copy
    }
}
