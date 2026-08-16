import CoreGraphics
import Foundation
import LuminaCore
import SwiftUI

/// Spielt eine Bildanimation im Stream ab: ein Hintergrund-Task dekodiert die Frames
/// der Reihe nach voraus, die Anzeige holt sie im Takt der Frame-Delays ab.
///
/// Dadurch startet die Wiedergabe nach dem ersten Frame statt nach der kompletten
/// Datei, und der Speicherbedarf bleibt unabhängig von der Länge konstant.
@MainActor
final class AnimationPlayback: ObservableObject {
    @Published private(set) var frame: CGImage?

    /// Wie viele Frames maximal vorausdekodiert werden.
    ///
    /// Bei 900x500 sind das rund 43 MB. Genug, um Schwankungen der Dekodierzeit
    /// abzufangen, ohne den Speicher volllaufen zu lassen.
    private let bufferCapacity = 24

    private let url: URL
    private let maxPixelSize: Int
    private var queue: [TimedFrame] = []
    private var producer: Task<Void, Never>?
    private var consumer: Task<Void, Never>?
    private var isPaused: Bool

    init(url: URL, maxPixelSize: Int, isPaused: Bool) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.isPaused = isPaused
    }

    func start() {
        guard producer == nil else { return }

        let url = self.url
        let maxPixelSize = self.maxPixelSize
        let capacity = bufferCapacity

        producer = Task.detached(priority: .userInitiated) { [weak self] in
            guard let decoder = AnimationDecoder(url: url, maxPixelSize: maxPixelSize) else { return }

            while !Task.isCancelled {
                // Backpressure: ist der Puffer voll, wird nicht weiter dekodiert.
                // Das hält auch bei Pause die CPU ruhig.
                while true {
                    guard let count = await self?.queueCount else { return }
                    if count < capacity { break }
                    try? await Task.sleep(for: .milliseconds(20))
                    if Task.isCancelled { return }
                }
                guard let frame = decoder.next() else {
                    // Defekter Frame: weiter, aber nicht heisslaufen.
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                }
                await self?.enqueue(frame)
            }
        }

        consumer = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        producer?.cancel()
        consumer?.cancel()
        producer = nil
        consumer = nil
        queue.removeAll()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    // MARK: - Puffer

    private var queueCount: Int { queue.count }

    private func enqueue(_ frame: TimedFrame) {
        queue.append(frame)
    }

    private func dequeue() -> TimedFrame? {
        queue.isEmpty ? nil : queue.removeFirst()
    }

    /// Zeigt Frames im Takt ihrer Delays. Bei leerem Puffer wird kurz gewartet,
    /// statt das Bild zurückzusetzen.
    private func run() async {
        while !Task.isCancelled {
            if isPaused {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }
            guard let next = dequeue() else {
                try? await Task.sleep(for: .milliseconds(10))
                continue
            }
            frame = next.image
            try? await Task.sleep(for: .seconds(next.delay))
        }
    }

    deinit {
        producer?.cancel()
        consumer?.cancel()
    }
}
