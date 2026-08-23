import AppKit
import Foundation
import LuminaCore
import Sparkle
import SwiftUI

/// Bindeglied zwischen Sparkle und der Oberfläche.
///
/// Sparkle übernimmt Download, Prüfung der EdDSA-Signatur, den Austausch des
/// Bundles und den Neustart. Selbst gebaut wäre jeder dieser Schritte eine
/// Sicherheitslücke in Wartung: eine laufende App kann sich nicht selbst ersetzen,
/// und ohne Signaturprüfung wird der Update-Weg zum Einfallstor.
@MainActor
final class UpdateModel: NSObject, ObservableObject {
    /// Ob gerade nach Updates gesucht werden kann. Während einer laufenden Suche
    /// oder Installation sperrt Sparkle die Aktion.
    @Published private(set) var canCheck = true
    /// Letzte Rückmeldung für die Anzeige im Einstellungen-Fenster.
    @Published private(set) var lastResult: Result?

    enum Result: Equatable {
        case upToDate(Date)
        case found(String)
        case failed(String)
    }

    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    static var installedVersion: SemanticVersion {
        let string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return SemanticVersion(string) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    override init() {
        super.init()
        // startingUpdater: true lässt Sparkle die geplante Suche selbst übernehmen.
        // Der Rhythmus steht in der Info.plist (SUScheduledCheckInterval).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        observation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in self?.canCheck = updater.canCheckForUpdates }
        }
    }

    /// Ob Sparkle beim Start automatisch suchen soll.
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

    /// Sucht auf Wunsch des Benutzers. Findet Sparkle etwas, zeigt es selbst den
    /// Dialog mit "Jetzt installieren", "Beim Beenden" und "Später".
    func checkNow() {
        lastResult = nil
        controller?.checkForUpdates(nil)
    }
}

extension UpdateModel: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in lastResult = .found(version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in lastResult = .upToDate(Date()) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // Abbruch durch den Benutzer ist kein Fehler und gehört nicht gemeldet.
        let cancelled = (error as NSError).code == Int(Sparkle.SUError.installationCanceledError.rawValue)
        guard !cancelled else { return }
        let message = error.localizedDescription
        Task { @MainActor in lastResult = .failed(message) }
    }
}
