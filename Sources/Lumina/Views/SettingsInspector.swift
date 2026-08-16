import LuminaCore
import SwiftUI

/// Einstellungs-Sidebar des Hauptfensters.
///
/// Die Sections sind bewusst in eigene Properties zerlegt - ein einziger grosser
/// Form-Body überfordert den Typechecker von SwiftUI.
struct SettingsInspector: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            presetSection
            timingSection
            appearanceSection
            orderSection
            playbackSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 300)
        .onChange(of: app.config.sortOrder) { _, _ in app.resort() }
        .onChange(of: app.config.ascending) { _, _ in app.resort() }
        .onChange(of: app.config.recursiveImport) { _, _ in
            Task { await app.reload() }
        }
        .onChange(of: app.config.slideDuration) { _, _ in
            // Ein Übergang, der länger dauert als die Standzeit, würde das Bild nie ruhen lassen.
            let limit = app.config.slideDuration * 0.8
            if app.config.transitionDuration > limit {
                app.config.transitionDuration = limit
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var presetSection: some View {
        Section("Vorlagen") {
            HStack(spacing: 8) {
                ForEach(SlideshowPreset.all) { preset in
                    Button(preset.name) { applyPreset(preset) }
                        .help(preset.hint)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var timingSection: some View {
        Section("Zeiten") {
            LabeledContent("Anzeigedauer") {
                sliderRow(value: $app.config.slideDuration, range: 1...60, step: 0.5)
            }
            LabeledContent("Übergangsdauer") {
                sliderRow(value: $app.config.transitionDuration, range: 0...3, step: 0.1)
            }
            .disabled(app.config.transition == .cut)
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Darstellung") {
            Picker("Übergang", selection: $app.config.transition) {
                ForEach(TransitionStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            Picker("Bildanpassung", selection: $app.config.scaleMode) {
                ForEach(ScaleMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Picker("Zoom-Fahrt", selection: $app.config.kenBurns) {
                ForEach(KenBurnsIntensity.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Hintergrund") {
                HStack {
                    Slider(value: $app.config.backgroundBrightness, in: 0...1)
                    Text(brightnessLabel)
                        .font(.callout.monospacedDigit())
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var orderSection: some View {
        Section("Reihenfolge") {
            Picker("Sortierung", selection: $app.config.sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            Toggle("Aufsteigend", isOn: $app.config.ascending)
                .disabled(app.config.sortOrder == .shuffled)
            if app.config.sortOrder == .shuffled {
                Button("Neu mischen") { app.reshuffle() }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var playbackSection: some View {
        Section("Ablauf") {
            Toggle("Endlos wiederholen", isOn: $app.config.loop)
            Toggle("Im Vollbild starten", isOn: $app.config.startFullscreen)
            Toggle("Dateiname einblenden", isOn: $app.config.showFilename)
            Toggle("Fortschrittsbalken", isOn: $app.config.showProgress)
            Toggle("Unterordner einbeziehen", isOn: $app.config.recursiveImport)
        }
    }

    // MARK: - Bausteine

    @ViewBuilder
    private func sliderRow(value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Slider(value: value, in: range, step: step)
            Text(seconds(value.wrappedValue))
                .font(.callout.monospacedDigit())
                .frame(width: 58, alignment: .trailing)
        }
    }

    private var brightnessLabel: String {
        app.config.backgroundBrightness < 0.02
            ? "Schwarz"
            : "\(Int(app.config.backgroundBrightness * 100)) %"
    }

    private func seconds(_ value: Double) -> String {
        value < 10
            ? String(format: "%.1f s", value)
            : String(format: "%.0f s", value)
    }

    private func applyPreset(_ preset: SlideshowPreset) {
        app.config = preset.apply(app.config)
    }
}

/// Fertige Kombinationen für die häufigsten Anwendungsfälle.
struct SlideshowPreset: Identifiable {
    let id: String
    let name: String
    let hint: String
    let apply: (SlideshowConfig) -> SlideshowConfig

    static let all: [SlideshowPreset] = [
        SlideshowPreset(
            id: "screensaver",
            name: "Bildschirmschoner",
            hint: "Langsam, weiche Überblendung, ruhige Zoom-Fahrt, Bild formatfüllend"
        ) { config in
            var next = config
            next.slideDuration = 8
            next.transitionDuration = 2
            next.transition = .crossfade
            next.scaleMode = .fill
            next.kenBurns = .medium
            next.loop = true
            next.showProgress = false
            next.showFilename = false
            return next.sanitized()
        },
        SlideshowPreset(
            id: "diashow",
            name: "Diaschau",
            hint: "Mittleres Tempo, wechselnde Effekte, ganzes Bild sichtbar"
        ) { config in
            var next = config
            next.slideDuration = 5
            next.transitionDuration = 1
            next.transition = .random
            next.scaleMode = .fitBlurred
            next.kenBurns = .subtle
            next.loop = true
            next.showProgress = true
            return next.sanitized()
        },
        SlideshowPreset(
            id: "presentation",
            name: "Präsentation",
            hint: "Harte Schnitte, kein Zoom, ganzes Bild, ohne Wiederholung"
        ) { config in
            var next = config
            next.slideDuration = 10
            next.transitionDuration = 0
            next.transition = .cut
            next.scaleMode = .fit
            next.kenBurns = .off
            next.loop = false
            next.showProgress = true
            next.showFilename = true
            return next.sanitized()
        },
    ]
}
