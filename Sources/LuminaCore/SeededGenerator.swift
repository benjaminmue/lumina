import Foundation

/// Deterministischer PRNG (SplitMix64).
///
/// Wird gebraucht, damit Ken-Burns-Bewegung, Zufallsübergang und die Zufallssortierung
/// bei jedem Rendern desselben Bildes identisch ausfallen. Ohne festen Seed würde
/// SwiftUI bei jedem Redraw neue Werte ziehen und das Bild sichtbar springen.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        // Seed 0 würde bei SplitMix64 eine degenerierte Folge liefern.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public extension String {
    /// Stabiler 64-Bit-Hash (FNV-1a).
    ///
    /// `String.hashValue` ist pro Prozessstart zufällig geseedet und taugt darum nicht
    /// als Seed für reproduzierbare Animationen.
    var stableHash: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01B3
        }
        return hash
    }
}
