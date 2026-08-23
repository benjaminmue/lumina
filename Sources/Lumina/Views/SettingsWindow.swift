import AppKit
import LuminaCore
import SwiftUI

/// Das Einstellungen-Fenster (Cmd-Komma).
///
/// Abgrenzung zur Sidebar im Hauptfenster: dort steht, was eine einzelne Show
/// ausmacht und was Vorlagen überschreiben. Hier steht, was man einmal einstellt.
struct SettingsWindow: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            PlaybackPane()
                .tabItem { Label("Playback", systemImage: "play.display") }
            UpdatePane()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .environmentObject(app)
        .frame(width: 480)
    }
}

// MARK: - Allgemein

private struct GeneralPane: View {
    @EnvironmentObject private var app: AppState

    /// Die Oberfläche folgt sofort der Environment-Locale. `AppleLanguages` wird
    /// zusätzlich gesetzt, damit die vom System gestellten Teile (Menüleiste,
    /// Standarddialoge) beim nächsten Start nachziehen.
    private var languageBinding: Binding<AppLanguage?> {
        Binding(
            get: { app.preferences.language },
            set: { newValue in
                app.preferences.language = newValue
                if let newValue {
                    UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Interface language", selection: languageBinding) {
                    Text("Follow the system").tag(nil as AppLanguage?)
                    Divider()
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.endonym).tag(language as AppLanguage?)
                    }
                }
            } header: {
                Text("Language")
            } footer: {
                Text("The menu bar changes after the next restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("At launch") {
                Toggle("Load the last sources again", isOn: $app.preferences.restoreSession)
                    .help("Read the folders you last chose when opening the app")
            }

            Section("Import") {
                Toggle("Read subfolders too", isOn: $app.preferences.recursiveImport)
                Toggle("Ask before clearing the list", isOn: $app.preferences.confirmClear)
            }
        }
        .formStyle(.grouped)
        .onChange(of: app.preferences.recursiveImport) { _, _ in
            Task { await app.reload() }
        }
    }
}

// MARK: - Wiedergabe

private struct PlaybackPane: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Section("Start") {
                Toggle("Start in full screen", isOn: $app.preferences.startFullscreen)
            }

            Section("While playing") {
                Toggle("Keep the Mac awake", isOn: $app.preferences.preventSleep)
                    .help("Stops the screen saver or sleep from interrupting a running slideshow")

                Toggle("Play animations in full", isOn: $app.preferences.playAnimationsFully)
                    .help("Animated WebP, GIF and APNG run through at least once, even if the time per image is shorter")

                LabeledContent("Hide the pointer") {
                    HStack {
                        Slider(
                            value: $app.preferences.cursorHideDelay,
                            in: AppPreferences.cursorDelayRange,
                            step: 0.5
                        )
                        Text(String(format: "after %.1f s", app.preferences.cursorHideDelay))
                            .font(.callout.monospacedDigit())
                            .frame(width: 88, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Aktualisierung

private struct UpdatePane: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var model = UpdateModel()
    @State private var automatic = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed") {
                    Text(UpdateModel.installedVersion.description)
                        .foregroundStyle(.secondary)
                }

                if let date = model.lastCheckDate {
                    LabeledContent("Last checked") {
                        Text(date.formatted(.relative(presentation: .named)))
                            .foregroundStyle(.secondary)
                    }
                }

                // Sparkle bringt seinen eigenen Dialog mit: installieren, beim
                // Beenden installieren oder später erinnern. Hier steht nur das
                // Ergebnis der letzten Suche.
                switch model.lastResult {
                case .some(.upToDate):
                    Label {
                        Text("Lumina \(UpdateModel.installedVersion.description) is up to date.")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                case .some(.found(let version)):
                    Label {
                        Text("Version \(version) is available.")
                    } icon: {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                    }
                case .some(.failed(let reason)):
                    Label {
                        Text("Check failed.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .none:
                    EmptyView()
                }

                Button("Check for updates") { model.checkNow() }
                    .disabled(!model.canCheck)
            }

            Section {
                Toggle("Check automatically", isOn: $automatic)
                    .onChange(of: automatic) { _, newValue in
                        model.automaticallyChecks = newValue
                    }
            } footer: {
                Text("Updates install themselves from inside the app. Asks the releases page on GitHub, which is the only network access the app makes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { automatic = model.automaticallyChecks }
    }
}

// MARK: - Über

private struct AboutPane: View {
    private let repoURL = URL(string: "https://github.com/benjaminmue/lumina")!
    private let profileURL = URL(string: "https://github.com/benjaminmue")!

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Lumina").font(.largeTitle.bold())

            // Bewusst unübersetzt: die Selbstironie gehört zum Namen.
            Text("Just another Mac slideshow app")
                .foregroundStyle(.secondary)

            Text("Version \(UpdateModel.installedVersion.description) (build \(UpdateModel.buildNumber))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider().padding(.vertical, 6)

            HStack(spacing: 18) {
                Link("Benjamin Mueller", destination: profileURL)
                Link("Source code", destination: repoURL)
            }
            .font(.callout)

            HStack(spacing: 10) {
                Button("Report a bug") { openIssue(template: "bug_report.yml") }
                Button("Request a feature") { openIssue(template: "feature_request.yml") }
            }
            .padding(.top, 2)

            Link(
                "MIT license",
                destination: repoURL.appendingPathComponent("blob/main/LICENSE")
            )
            .font(.caption2)
            .padding(.top, 6)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    /// Öffnet das passende Formular auf GitHub und füllt aus, was die App selbst weiss.
    ///
    /// Die Namen der Parameter sind die `id`-Werte der Felder in der YAML-Vorlage.
    /// Wer von hier aus meldet, muss Version und Systemversion nicht abtippen -
    /// und sie stimmen dann auch.
    private func openIssue(template: String) {
        var components = URLComponents(
            url: repoURL.appendingPathComponent("issues/new"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "template", value: template),
            URLQueryItem(name: "version", value: UpdateModel.installedVersion.description),
            URLQueryItem(name: "macos", value: Self.systemVersion),
        ]
        NSWorkspace.shared.open(components?.url ?? repoURL.appendingPathComponent("issues"))
    }

    /// macOS-Version als "26.5" beziehungsweise "26.5.2".
    private static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"
    }
}
