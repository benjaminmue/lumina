import AppKit
import Foundation
import LuminaCore
import SwiftUI

/// Zustand der Update-Suche.
@MainActor
final class UpdateModel: ObservableObject {
    enum Phase: Equatable {
        case never
        case checking
        case upToDate(Date)
        case available(ReleaseInfo)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .never

    static let owner = "benjaminmue"
    static let repo = "lumina"

    /// Installierte Version aus dem Bundle.
    static var installedVersion: SemanticVersion {
        let string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return SemanticVersion(string) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    init(preferences: AppPreferences) {
        if let last = preferences.lastUpdateCheck {
            phase = .upToDate(last)
        }
    }

    /// Sucht nach einer neueren Version.
    ///
    /// - Parameter preferences: wird für Zeitstempel und übersprungene Version
    ///   gelesen und geschrieben.
    func check(preferences: Binding<AppPreferences>) async {
        phase = .checking

        let result = await UpdateChecker.latestRelease(owner: Self.owner, repo: Self.repo)
        let now = Date()
        preferences.wrappedValue.lastUpdateCheck = now

        switch result {
        case .success(let release):
            // Eine übersprungene Version bleibt still, bis eine neuere erscheint.
            if preferences.wrappedValue.shouldAnnounce(release.version, current: Self.installedVersion) {
                phase = .available(release)
            } else {
                phase = .upToDate(now)
            }
        case .failure(let error):
            phase = .failed(error.localizedDescription ?? String(localized: "Check failed."))
        }
    }

    /// Meldet diese Version nicht mehr.
    func skip(_ release: ReleaseInfo, preferences: Binding<AppPreferences>) {
        preferences.wrappedValue.skippedVersion = release.version.description
        phase = .upToDate(Date())
    }
}
