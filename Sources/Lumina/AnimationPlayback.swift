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

    /// Obergrenzen des Vorlaufs.
    ///
    /// Die Byte-Grenze ist die entscheidende: die Frame-Grösse hängt an der Auflösung
    /// der Datei und schwankt um mehr als den Faktor 50. Eine Grenze allein nach
    /// Frame-Anzahl liesse bei grossen Vorlagen den Speicher volllaufen.
    ///
    /// Sie wirkt weich: geprüft wird vor dem Dekodieren, die Grösse des nächsten
    /// Frames steht erst danach fest. Überschritten wird sie also um höchstens einen
    /// Frame. Da der Decoder auf die Anzeigegrösse begrenzt ist, sind das bei einem
    /// 5K-Bildschirm rund 26 MB.
    private let bufferFrames = 24
    private let bufferBytes = 64 * 1024 * 1024

    private let url: URL
    private let maxPixelSize: Int
    private var queue: [TimedFrame] = []
    private var queuedBytes = 0
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

        producer = Task.detached(priority: .userInitiated) { [weak self] in
            guard let decoder = AnimationDecoder(url: url, maxPixelSize: maxPixelSize) else { return }
            var consecutiveFailures = 0

            while !Task.isCancelled {
                // Backpressure: ist der Puffer voll, wird nicht weiter dekodiert.
                // Das hält auch bei Pause die CPU ruhig.
                while true {
                    guard let hasSpace = await self?.hasBufferSpace else { return }
                    if hasSpace { break }
                    try? await Task.sleep(for: .milliseconds(20))
                    if Task.isCancelled { return }
                }

                guard let frame = decoder.next() else {
                    consecutiveFailures += 1
                    // Nach einer vollen Runde ohne einen einzigen brauchbaren Frame
                    // ist die Datei nicht abspielbar - dann übernimmt das Standbild,
                    // statt dass der Task mit 100 Hz ins Leere läuft.
                    guard consecutiveFailures < max(decoder.frameCount, 8) else { return }
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                }

                consecutiveFailures = 0
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
        queuedBytes = 0
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    // MARK: - Puffer

    private var hasBufferSpace: Bool {
        queue.count < bufferFrames && queuedBytes < bufferBytes
    }

    private func enqueue(_ frame: TimedFrame) {
        queue.append(frame)
        queuedBytes += frame.image.bytesPerRow * frame.image.height
    }

    private func dequeue() -> TimedFrame? {
        guard !queue.isEmpty else { return nil }
        let frame = queue.removeFirst()
        queuedBytes = max(0, queuedBytes - frame.image.bytesPerRow * frame.image.height)
        return frame
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
