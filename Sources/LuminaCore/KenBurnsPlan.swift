import CoreGraphics
import Foundation

/// Start- und Endzustand der langsamen Kamerafahrt über ein Bild.
///
/// Die Werte sind relativ: `scale` ist ein Zoom-Faktor, `offset` ein Anteil der
/// jeweiligen Kantenlänge. Die View multipliziert das mit ihrer echten Grösse.
public struct KenBurnsPlan: Equatable, Sendable {
    public let startScale: CGFloat
    public let endScale: CGFloat
    public let startOffset: CGSize
    public let endOffset: CGSize

    public static let still = KenBurnsPlan(
        startScale: 1, endScale: 1, startOffset: .zero, endOffset: .zero
    )

    public init(startScale: CGFloat, endScale: CGFloat, startOffset: CGSize, endOffset: CGSize) {
        self.startScale = startScale
        self.endScale = endScale
        self.startOffset = startOffset
        self.endOffset = endOffset
    }

    /// Erzeugt eine reproduzierbare Fahrt für ein Bild.
    ///
    /// - Parameters:
    ///   - seed: Stabiler Seed des Bildes (`MediaItem.seed`).
    ///   - intensity: Vom Benutzer gewählte Stärke.
    public static func make(seed: UInt64, intensity: KenBurnsIntensity) -> KenBurnsPlan {
        guard intensity != .off else { return .still }

        var rng = SeededGenerator(seed: seed)
        let zoom = intensity.zoomRange
        let pan = intensity.panAmount

        // Die Hälfte der Bilder zoomt rein, die andere raus - das wirkt weniger monoton.
        let zoomsIn = Bool.random(using: &rng)
        let amplitude = CGFloat(Double.random(in: (zoom.upperBound - 1) * 0.6...(zoom.upperBound - 1), using: &rng))
        let low: CGFloat = 1.0
        let high: CGFloat = 1.0 + amplitude

        // Bei Zoom muss immer die grössere Skalierung als Basis dienen, sonst
        // entstehen im ausgezoomten Zustand leere Ränder.
        let startScale = zoomsIn ? low : high
        let endScale = zoomsIn ? high : low

        // Schwenkrichtung: eine der acht Himmelsrichtungen, Länge zufällig.
        let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
        let distance = Double.random(in: pan * 0.4...pan, using: &rng)
        let dx = CGFloat(cos(angle) * distance)
        let dy = CGFloat(sin(angle) * distance)

        return KenBurnsPlan(
            startScale: startScale,
            endScale: endScale,
            startOffset: CGSize(width: -dx / 2, height: -dy / 2),
            endOffset: CGSize(width: dx / 2, height: dy / 2)
        )
    }
}
