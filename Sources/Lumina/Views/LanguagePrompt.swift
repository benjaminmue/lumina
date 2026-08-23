import LuminaCore
import SwiftUI

/// Einmalige Sprachwahl beim ersten Start.
///
/// Erscheint nur, wenn das System eine Sprache verlangt, die es hier nicht gibt.
/// Wer Deutsch oder Japanisch eingestellt hat, bekommt die App wortlos in seiner
/// Sprache und sieht dieses Fenster nie.
struct LanguagePrompt: View {
    @Binding var preferences: AppPreferences
    @State private var choice: AppLanguage = .english

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Choose your language")
                    .font(.title2)
                Text("Lumina is not available in your system language. Pick one:")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Picker("", selection: $choice) {
                ForEach(AppLanguage.allCases) { language in
                    // Jede Sprache in sich selbst: so findet sich jeder wieder,
                    // unabhängig davon, welche gerade aktiv ist.
                    Text(language.endonym).tag(language)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Button("Continue") {
                preferences.language = choice
                preferences.didAskForLanguage = true
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 380)
        // Der Dialog selbst erscheint in der gerade gewählten Sprache.
        .environment(\.locale, choice.locale)
    }
}
