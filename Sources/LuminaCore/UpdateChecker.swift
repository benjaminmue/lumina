import Foundation
import os

private let updateLog = Logger(subsystem: "ch.bebamu.lumina", category: "updates")

/// Version nach dem Muster `major.minor.patch`.
///
/// Bewusst eigener Typ statt String-Vergleich: "1.10.0" ist grösser als "1.9.0",
/// als Zeichenkette verglichen wäre es kleiner.
public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Nimmt `1.2.3` und `v1.2.3`, ebenso verkürzte Formen wie `1.2` oder `2`.
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        // Ein Tag, der mit einem Trennzeichen beginnt, ist keine Version. Ohne diese
        // Prüfung würde "-1.0.0" beim Abschneiden der Vorabversion zu "1.0.0".
        guard !text.isEmpty, !text.hasPrefix("-"), !text.hasPrefix("+") else { return nil }

        // Vorabversionen und Build-Angaben abschneiden: 1.2.0-beta.1+build5
        let core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
        let head = core.split(separator: "+", maxSplits: 1).first.map(String.init) ?? core

        let parts = head.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }

        self.major = numbers[0]
        self.minor = numbers[1]
        self.patch = numbers[2]
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// Ein Release auf GitHub.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let tag: String
    public let pageURL: URL
    public let downloadURL: URL?
    public let publishedAt: Date?
    public let notes: String?

    public init(
        version: SemanticVersion,
        tag: String,
        pageURL: URL,
        downloadURL: URL?,
        publishedAt: Date?,
        notes: String?
    ) {
        self.version = version
        self.tag = tag
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
        self.notes = notes
    }
}

/// Fragt das neueste Release auf GitHub ab.
///
/// Das ist der einzige Netzwerkzugriff der App. Er passiert nur, wenn der Benutzer
/// ihn auslöst oder die automatische Suche eingeschaltet hat.
public enum UpdateChecker {

    public enum Failure: Error, LocalizedError, Equatable {
        case noRelease
        case rateLimited
        case server(Int)
        case malformed
        case network(String)

        public var errorDescription: String? {
            switch self {
            case .noRelease:
                return String(localized: "There is no release yet.")
            case .rateLimited:
                return String(localized: "GitHub received too many requests. Please try again later.")
            case .server(let code):
                return String(localized: "GitHub answered with error \(code).")
            case .malformed:
                return String(localized: "The answer from GitHub could not be read.")
            case .network(let reason):
                return reason
            }
        }
    }

    public static func latestRelease(
        owner: String,
        repo: String,
        session: URLSession = .shared
    ) async -> Result<ReleaseInfo, Failure> {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            return .failure(.malformed)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Lumina", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200: break
                case 404: return .failure(.noRelease)
                // GitHub antwortet bei erschöpftem Kontingent mit 403 oder 429.
                case 403, 429: return .failure(.rateLimited)
                default: return .failure(.server(http.statusCode))
                }
            }

            guard let info = parse(data) else { return .failure(.malformed) }
            return .success(info)
        } catch {
            updateLog.notice("Update-Abfrage fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return .failure(.network(error.localizedDescription))
        }
    }

    /// Liest die Antwort der GitHub-API. Getrennt von der Abfrage, damit es ohne Netz testbar ist.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String,
              let version = SemanticVersion(tag),
              let pageString = root["html_url"] as? String,
              let pageURL = URL(string: pageString)
        else { return nil }

        // Das Disk-Image ist das einzige Anhängsel, das den Benutzer interessiert.
        let assets = root["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        let downloadURL = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))

        let published = (root["published_at"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        }

        let notes = (root["body"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return ReleaseInfo(
            version: version,
            tag: tag,
            pageURL: pageURL,
            downloadURL: downloadURL,
            publishedAt: published,
            notes: notes
        )
    }
}
