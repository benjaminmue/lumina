import LuminaCore
import SwiftUI

/// Einstellungs-Sidebar des Hauptfensters.
///
/// Drei Ebenen: Vorlagen und die vier Regler, die man ständig anfasst, stehen oben.
/// Reihenfolge in der Mitte. Alles, was man einmal einstellt und dann vergisst,
/// liegt eingeklappt darunter.
struct SettingsInspector: View {
    @EnvironmentObject private var app: AppState
    @State private var showsMoreOptions = false

    var body: some View {
        Form {
            presetSection
            playbackSection
            orderSection
            moreSection
        }
        .formStyle(.grouped)
        .animation(.snappy(duration: 0.2), value: app.config.transition == .cut)
        .onChange(of: app.config.sortOrder) { _, _ in app.resort() }
        .onChange(of: app.config.ascending) { _, _ in app.resort() }
        .onChange(of: app.config.slideDuration) { _, _ in
            // Ein Übergang, der länger dauert als die Standzeit, würde das Bild nie
            // ruhen lassen. Die Regel steht in sanitized() und wird hier nur angewandt.
            app.config = app.config.sanitized()
        }
    }

    // MARK: - Vorlagen

    @ViewBuilder
    private var presetSection: some View {
        Section {
            VStack(spacing: 8) {
                ForEach(SlideshowPreset.all) { preset in
                    PresetCard(
                        preset: preset,
                        isActive: preset.matches(app.config),
                        action: { app.config = preset.apply(app.config) }
                    )
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    // MARK: - Wiedergabe

    @ViewBuilder
    private var playbackSection: some View {
        Section("Playback") {
            LabeledContent("Time per image") {
                sliderRow(value: $app.config.slideDuration, range: SlideshowConfig.durationRange, step: 0.5)
            }

            Picker("Transition", selection: $app.config.transition) {
                ForEach(TransitionStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }

            // Ausblenden statt ausgrauen: ein deaktivierter Regler ist nur Ballast.
            if app.config.transition != .cut {
                LabeledContent("Transition duration") {
                    sliderRow(value: $app.config.transitionDuration, range: SlideshowConfig.transitionRange, step: 0.1)
                }
            }

            Picker("Scaling", selection: $app.config.scaleMode) {
                ForEach(ScaleMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("Camera move", selection: $app.config.kenBurns) {
                ForEach(KenBurnsIntensity.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Reihenfolge

    @ViewBuilder
    private var orderSection: some View {
        Section("Order") {
            Picker("Sort by", selection: $app.config.sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            if app.config.sortOrder == .shuffled {
                Button("Shuffle again") { app.reshuffle() }
            } else {
                Toggle("Ascending", isOn: $app.config.ascending)
            }
            Toggle("Repeat forever", isOn: $app.config.loop)
        }
    }

    // MARK: - Selten Gebrauchtes

    @ViewBuilder
    private var moreSection: some View {
        Section {
            // Nur noch, was zur einzelnen Show gehört. Vollbildstart, Import und
            // Animationsverhalten stehen im Einstellungen-Fenster.
            DisclosureGroup("Overlays", isExpanded: $showsMoreOptions) {
                Toggle("Show file name", isOn: $app.config.showFilename)
                Toggle("Progress bar", isOn: $app.config.showProgress)

                LabeledContent("Background") {
                    HStack {
                        Slider(value: $app.config.backgroundBrightness, in: 0...1)
                        Text(brightnessLabel)
                            .font(.callout.monospacedDigit())
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
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

    private var brightnessLabel: LocalizedStringResource {
        app.config.backgroundBrightness < 0.02
            ? "Black"
            : "\(Int(app.config.backgroundBrightness * 100)) %"
    }

    private func seconds(_ value: Double) -> String {
        value < 10
            ? String(format: "%.1f s", value)
            : String(format: "%.0f s", value)
    }
}

/// Auswahlkarte für eine Vorlage.
private struct PresetCard: View {
    let preset: SlideshowPreset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: preset.symbol)
                    .font(.title3)
                    .frame(width: 26)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .font(.callout.weight(.medium))
                    Text(preset.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: isActive ? 1.5 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// Fertige Kombinationen für die häufigsten Anwendungsfälle.
struct SlideshowPreset: Identifiable {
    let id: String
    /// `LocalizedStringResource`, nicht `String`: ein fertiger String wird von
    /// SwiftUI nicht mehr übersetzt, die Karten blieben sonst englisch.
    let name: LocalizedStringResource
    let symbol: String
    let hint: LocalizedStringResource
    let apply: (SlideshowConfig) -> SlideshowConfig

    /// Ob die aktuellen Einstellungen dieser Vorlage entsprechen.
    ///
    /// Verglichen wird über das Ergebnis der Vorlage selbst, damit Felder, die eine
    /// Vorlage gar nicht anfasst, keine Rolle spielen.
    func matches(_ config: SlideshowConfig) -> Bool {
        apply(config) == config
    }

    static let all: [SlideshowPreset] = [
        SlideshowPreset(
            id: "screensaver",
            name: "Screen saver",
            symbol: "moon.stars",
            hint: "Slow, soft crossfade, calm camera move"
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
            name: "Slide show",
            symbol: "sparkles.rectangle.stack",
            hint: "Medium pace, changing effects, whole image"
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
            name: "Presentation",
            symbol: "rectangle.on.rectangle",
            hint: "Hard cuts, no zoom, no repeat"
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
