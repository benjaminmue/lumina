import Foundation

/// Zeitachse einer Bildanimation: welcher Frame ist zu welchem Zeitpunkt sichtbar.
///
/// Bewusst ohne Bilddaten, damit sich die Frame-Auswahl ohne echte Dateien testen lässt.
public struct FrameTimeline: Equatable, Sendable {
    /// Anzeigedauer je Frame in Sekunden, bereits bereinigt.
    public let delays: [Double]
    /// Endzeitpunkt jedes Frames, aufsummiert.
    public let cumulative: [Double]
    public let totalDuration: Double

    /// Browser und Systemviewer behandeln extrem kurze Delays als "so schnell wie möglich"
    /// und setzen sie auf 100 ms. Ohne diese Korrektur laufen alte GIFs unnatürlich schnell.
    public static let minimumDelay: Double = 0.011
    public static let defaultDelay: Double = 0.1

    public init(delays: [Double]) {
        let cleaned = delays.map { $0 < Self.minimumDelay ? Self.defaultDelay : $0 }
        self.delays = cleaned

        var running: Double = 0
        self.cumulative = cleaned.map { delay in
            running += delay
            return running
        }
        self.totalDuration = running
    }

    public var frameCount: Int { delays.count }

    /// Frame-Index zum Zeitpunkt `time` (Sekunden seit Animationsstart, läuft im Kreis).
    public func index(at time: Double) -> Int {
        guard frameCount > 1, totalDuration > 0 else { return 0 }

        // truncatingRemainder liefert bei negativen Zeiten ein negatives Ergebnis.
        var position = time.truncatingRemainder(dividingBy: totalDuration)
        if position < 0 { position += totalDuration }

        // Binäre Suche: der erste Frame, dessen Endzeitpunkt hinter der Position liegt.
        var low = 0
        var high = cumulative.count - 1
        while low < high {
            let middle = (low + high) / 2
            if cumulative[middle] > position {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}
