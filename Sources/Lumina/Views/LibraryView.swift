import LuminaCore
import SwiftUI

/// Hauptfenster: Import, Bildauswahl und Einstellungen.
struct LibraryView: View {
    @EnvironmentObject private var app: AppState
    @State private var showInspector = true

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 14)]

    var body: some View {
        Group {
            if app.items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            SettingsInspector()
                .inspectorColumnWidth(min: 300, ideal: 330, max: 420)
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
        VStack(spacing: 22) {
            Image(systemName: "photo.stack")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
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
                Button {
                    Task { await app.addSources(FilePicker.chooseFolders()) }
                } label: {
                    Label("Ordner wählen", systemImage: "folder")
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(app.items) { item in
                    ThumbnailView(
                        item: item,
                        loader: app.thumbnailLoader,
                        isEnabled: app.isEnabled(item),
                        onToggle: { app.toggle(item) },
                        onPlayFromHere: { app.present(startingAt: item) }
                    )
                }
            }
            .padding(18)
        }
        .overlay(alignment: .bottom) { statusBar }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            if app.isImporting {
                ProgressView().controlSize(.small)
                Text("Lese Bilder …")
            } else {
                Text("\(app.playableItems.count) von \(app.items.count) Bildern ausgewählt")
            }

            Spacer()

            Text(estimatedRuntime)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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
        ToolbarItemGroup(placement: .navigation) {
            Button {
                Task { await app.addSources(FilePicker.chooseImages()) }
            } label: {
                Label("Bilder", systemImage: "photo.badge.plus")
            }
            .help("Einzelne Bilder hinzufügen (⌘O)")

            Button {
                Task { await app.addSources(FilePicker.chooseFolders()) }
            } label: {
                Label("Ordner", systemImage: "folder.badge.plus")
            }
            .help("Ordner hinzufügen (⇧⌘O)")
        }

        ToolbarItemGroup {
            if !app.items.isEmpty {
                Menu {
                    Button("Alle auswählen") { app.enableAll() }
                    Button("Keine auswählen") { app.disableAll() }
                    Button("Auswahl umkehren") { app.invertSelection() }
                    Divider()
                    Button("Liste leeren", role: .destructive) { app.clear() }
                } label: {
                    Label("Auswahl", systemImage: "checklist")
                }
            }

            Button {
                app.present()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(!app.canPresent)
            .keyboardShortcut("r", modifiers: .command)
            .help("Slideshow starten (⌘R)")

            Button {
                showInspector.toggle()
            } label: {
                Label("Einstellungen", systemImage: "sidebar.right")
            }
        }
    }
}
