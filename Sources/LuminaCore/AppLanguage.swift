import Foundation

/// Sprachen, in denen die Oberfläche vorliegt.
///
/// Der Standard ist die Systemsprache. Nur wenn das System eine Sprache verlangt,
/// die hier nicht vorkommt, wird der Benutzer einmalig gefragt - sonst stünde er
/// wortlos vor einer englischen Oberfläche.
public enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case italian = "it"
    case spanish = "es"
    case japanese = "ja"

    public var id: String { rawValue }

    /// Name in der jeweiligen Sprache selbst - so findet sich jeder wieder,
    /// unabhängig davon, welche Sprache gerade aktiv ist.
    public var endonym: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .italian: return "Italiano"
        case .spanish: return "Español"
        case .japanese: return "日本語"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    /// Die passende Sprache zu einem Sprachcode, auch wenn er eine Region trägt
    /// (`de-CH`, `pt-BR`) oder ein Schriftsystem nennt (`zh-Hans-CN`).
    public static func matching(_ identifier: String) -> AppLanguage? {
        let code = identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased()

        guard let code else { return nil }
        return AppLanguage(rawValue: code)
    }

    /// Erste unterstützte Sprache aus den Systemeinstellungen.
    ///
    /// - Parameter preferred: Sprachwünsche des Systems, in absteigender Priorität.
    /// - Returns: `nil`, wenn keine davon vorliegt - dann muss gefragt werden.
    public static func fromSystem(preferred: [String] = Locale.preferredLanguages) -> AppLanguage? {
        for identifier in preferred {
            if let match = matching(identifier) { return match }
        }
        return nil
    }
}
