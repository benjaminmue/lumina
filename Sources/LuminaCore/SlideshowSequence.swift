import Foundation

/// Reine Ablauf-Logik der Slideshow: welches Bild ist dran, was kommt als nächstes.
///
/// Bewusst ohne UI-Abhängigkeiten, damit sich Wraparound, Loop-Ende und
/// Vorausladen ohne laufendes Fenster testen lassen.
public struct SlideshowSequence: Equatable, Sendable {
    public private(set) var items: [MediaItem]
    public private(set) var index: Int
    /// Richtung des letzten Wechsels - steuert, ob "Schieben" nach links oder rechts läuft.
    public private(set) var lastDirection: Direction

    public enum Direction: Sendable, Equatable {
        case forward
        case backward
    }

    public init(items: [MediaItem], startIndex: Int = 0) {
        self.items = items
        self.index = items.isEmpty ? 0 : min(max(startIndex, 0), items.count - 1)
        self.lastDirection = .forward
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public var current: MediaItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    /// Springt ein Bild weiter.
    /// - Returns: `false`, wenn das Ende erreicht ist und `loop` aus ist.
    @discardableResult
    public mutating func advance(loop: Bool) -> Bool {
        guard !items.isEmpty else { return false }
        lastDirection = .forward
        if index + 1 < items.count {
            index += 1
            return true
        }
        guard loop else { return false }
        index = 0
        return true
    }

    /// Springt ein Bild zurück; am Anfang wird ans Ende gesprungen.
    public mutating func rewind() {
        guard !items.isEmpty else { return }
        lastDirection = .backward
        index = index == 0 ? items.count - 1 : index - 1
    }

    public mutating func jump(to newIndex: Int) {
        guard items.indices.contains(newIndex) else { return }
        lastDirection = newIndex >= index ? .forward : .backward
        index = newIndex
    }

    /// URLs, die als nächstes gebraucht werden - Kandidaten fürs Vorausladen.
    public func upcomingURLs(count lookahead: Int) -> [URL] {
        guard !items.isEmpty, lookahead > 0 else { return [] }
        return (1...lookahead).compactMap { offset in
            let next = (index + offset) % items.count
            return next == index ? nil : items[next].url
        }
    }
}
