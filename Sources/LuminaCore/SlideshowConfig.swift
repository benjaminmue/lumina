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

    /// Anzeigename.
    ///
    /// `LocalizedStringResource` statt `String`: der Text wird erst beim Anzeigen
    /// aufgelöst und folgt damit einer zur Laufzeit gewählten Sprache. Der Schlüssel
    /// ist der englische Text, damit eine fehlende Übersetzung lesbar bleibt.
    public var label: LocalizedStringResource {
        switch self {
        case .cut: return "Hard cut"
        case .crossfade: return "Crossfade"
        case .slide: return "Slide"
        case .push: return "Push"
        case .zoomBlur: return "Zoom"
        case .wipe: return "Wipe"
        case .flip: return "Flip"
        case .random: return "Random"
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

    public var label: LocalizedStringResource {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill (cropped)"
        case .fitBlurred: return "Fit with blurred edges"
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

    public var label: LocalizedStringResource {
        switch self {
        case .off: return "Off"
        case .subtle: return "Subtle"
        case .medium: return "Medium"
        case .strong: return "Strong"
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

    public var label: LocalizedStringResource {
        switch self {
        case .name: return "File name"
        case .dateCreated: return "Date created"
        case .dateModified: return "Date modified"
        case .fileSize: return "File size"
        case .shuffled: return "Shuffled"
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
    /// Animierte Bilder (WebP, GIF, APNG) mindestens einmal vollständig abspielen,
    /// auch wenn die Anzeigedauer kürzer ist.
    public var playAnimationsFully: Bool
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
        playAnimationsFully: Bool = true,
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
        self.playAnimationsFully = playAnimationsFully
        self.backgroundBrightness = backgroundBrightness
    }

    /// Fehlende Felder fallen auf ihren Standardwert zurück.
    ///
    /// Ohne das würde eine gespeicherte Einstellungsdatei aus einer älteren Version
    /// beim Dekodieren komplett scheitern und alle Einstellungen zurücksetzen,
    /// sobald ein neues Feld dazukommt.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SlideshowConfig()

        slideDuration = try container.decodeIfPresent(Double.self, forKey: .slideDuration) ?? fallback.slideDuration
        transitionDuration = try container.decodeIfPresent(Double.self, forKey: .transitionDuration) ?? fallback.transitionDuration
        transition = try container.decodeIfPresent(TransitionStyle.self, forKey: .transition) ?? fallback.transition
        scaleMode = try container.decodeIfPresent(ScaleMode.self, forKey: .scaleMode) ?? fallback.scaleMode
        kenBurns = try container.decodeIfPresent(KenBurnsIntensity.self, forKey: .kenBurns) ?? fallback.kenBurns
        sortOrder = try container.decodeIfPresent(SortOrder.self, forKey: .sortOrder) ?? fallback.sortOrder
        ascending = try container.decodeIfPresent(Bool.self, forKey: .ascending) ?? fallback.ascending
        recursiveImport = try container.decodeIfPresent(Bool.self, forKey: .recursiveImport) ?? fallback.recursiveImport
        loop = try container.decodeIfPresent(Bool.self, forKey: .loop) ?? fallback.loop
        startFullscreen = try container.decodeIfPresent(Bool.self, forKey: .startFullscreen) ?? fallback.startFullscreen
        showFilename = try container.decodeIfPresent(Bool.self, forKey: .showFilename) ?? fallback.showFilename
        showProgress = try container.decodeIfPresent(Bool.self, forKey: .showProgress) ?? fallback.showProgress
        playAnimationsFully = try container.decodeIfPresent(Bool.self, forKey: .playAnimationsFully) ?? fallback.playAnimationsFully
        backgroundBrightness = try container.decodeIfPresent(Double.self, forKey: .backgroundBrightness) ?? fallback.backgroundBrightness
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
