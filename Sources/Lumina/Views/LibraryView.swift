import LuminaCore
import SwiftUI

/// Hauptfenster: Import, Bildauswahl und Einstellungen.
struct LibraryView: View {
    @EnvironmentObject private var app: AppState
    @State private var showInspector = true
    @FocusState private var gridHasFocus: Bool

    /// Kachelmass und Abstand bestimmen zusammen die Spaltenzahl, die für die
    /// Pfeiltasten-Navigation gebraucht wird.
    private let tileMinimum: CGFloat = 168
    private let tileSpacing: CGFloat = 16
    private let gridPadding: CGFloat = 20

    var body: some View {
        Group {
            if app.items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .toolbar { toolbarContent }
        .searchable(text: $app.searchText, placement: .toolbar, prompt: "Bilder filtern")
        .inspector(isPresented: $showInspector) {
            SettingsInspector()
                .inspectorColumnWidth(min: 300, ideal: 320, max: 360)
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await app.addSources(urls) }
            return true
        }
        .alert(
            "Hinweis",
            isPresented: Binding(
                get: { app.errorMessage != nil },
                set: { if !$0 { app.errorMessage = nil } }
            )
        ) {
            Button("OK") { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
    }

    // MARK: - Zustände

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("Keine Bilder geladen")
                    .font(.title2)
                Text("Einzelne Bilder oder ganze Ordner wählen - oder Dateien hierher ziehen.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await app.addSources(FilePicker.chooseImages()) }
                } label: {
                    Label("Bilder wählen", systemImage: "photo")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await app.addSources(FilePicker.chooseFolders()) }
                } label: {
                    Label("Ordner wählen", systemImage: "folder")
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        GeometryReader { geo in
            let columns = columnCount(for: geo.size.width)
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: tileMinimum, maximum: 260), spacing: tileSpacing)],
                    alignment: .leading,
                    spacing: tileSpacing
                ) {
                    ForEach(app.visibleItems) { item in
                        ThumbnailView(
                            item: item,
                            loader: app.thumbnailLoader,
                            isEnabled: app.isEnabled(item),
                            isSelected: app.isSelected(item),
                            onSelect: { extend, toggle in
                                gridHasFocus = true
                                app.select(item, extend: extend, toggle: toggle)
                            },
                            onToggleInclusion: { app.toggleInclusion(item) },
                            onPlayFromHere: { app.present(startingAt: item) }
                        )
                    }
                }
                .padding(gridPadding)
            }
            // Klick ins Leere hebt die Markierung auf, wie im Finder.
            .contentShape(Rectangle())
            .onTapGesture { app.clearSelection() }
            .focusable()
            .focused($gridHasFocus)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .left: app.moveSelection(by: -1)
                case .right: app.moveSelection(by: 1)
                case .up: app.moveSelection(by: -columns)
                case .down: app.moveSelection(by: columns)
                @unknown default: break
                }
            }
            .onKeyPress(.space) {
                app.toggleInclusionOfSelection()
                return .handled
            }
            .onKeyPress(.return) {
                if let first = app.selectedItems.first {
                    app.present(startingAt: first)
                    return .handled
                }
                return .ignored
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        let usable = width - gridPadding * 2
        return max(1, Int((usable + tileSpacing) / (tileMinimum + tileSpacing)))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if app.isImporting {
                ProgressView().controlSize(.small)
                Text("Lese Bilder …")
            } else {
                Text("\(app.playableItems.count) von \(app.items.count) Bildern in der Slideshow")
                if !app.selection.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(app.selection.count) markiert")
                        .foregroundStyle(.secondary)
                }
                if !app.searchText.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(app.visibleItems.count) gefiltert")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(estimatedRuntime)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var estimatedRuntime: String {
        let total = Double(app.playableItems.count) * app.config.slideDuration
        guard total > 0 else { return "" }
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        return minutes > 0 ? "Laufzeit ca. \(minutes) min \(seconds) s" : "Laufzeit ca. \(seconds) s"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("Bilder …") {
                    Task { await app.addSources(FilePicker.chooseImages()) }
                }
                Button("Ordner …") {
                    Task { await app.addSources(FilePicker.chooseFolders()) }
                }
                Divider()
                // Gehört zum Import und nicht zu den Wiedergabe-Einstellungen.
                Toggle("Unterordner einbeziehen", isOn: $app.config.recursiveImport)
                Divider()
                Button("Liste leeren", role: .destructive) { app.clear() }
                    .disabled(app.items.isEmpty)
            } label: {
                Label("Hinzufügen", systemImage: "plus")
            }
            .help("Bilder oder Ordner hinzufügen")
        }

        ToolbarItemGroup {
            if !app.items.isEmpty {
                Menu {
                    Section("Markierung") {
                        Button("Alle markieren") { app.selectAll() }
                        Button("Markierung aufheben") { app.clearSelection() }
                            .disabled(app.selection.isEmpty)
                    }
                    Section("Slideshow") {
                        Button("Markierte umschalten") { app.toggleInclusionOfSelection() }
                            .disabled(app.selection.isEmpty)
                        Button("Nur Markierte behalten") { app.keepOnlySelected() }
                            .disabled(app.selection.isEmpty)
                        Divider()
                        Button("Alle aufnehmen") { app.enableAll() }
                        Button("Alle entfernen") { app.disableAll() }
                        Button("Umkehren") { app.invertInclusion() }
                    }
                } label: {
                    Label("Auswahl", systemImage: "checklist")
                }
            }

            Button {
                showInspector.toggle()
            } label: {
                Label("Einstellungen", systemImage: "sidebar.right")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                app.present()
            } label: {
                Label("Abspielen", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!app.canPresent)
            .help("Slideshow starten (⌘R)")
        }
    }
}
