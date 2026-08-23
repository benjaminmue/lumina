import LuminaCore
import SwiftUI

/// Hauptfenster: Import, Bildauswahl und Einstellungen.
struct LibraryView: View {
    @EnvironmentObject private var app: AppState
    @State private var showInspector = true
    @State private var showsClearConfirmation = false
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
        .confirmationDialog(
            "Clear the list?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { app.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The images stay on disk, only the selection is lost.")
        }
        .frame(minWidth: 900, minHeight: 620)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            SettingsInspector()
                .inspectorColumnWidth(min: 300, ideal: 320, max: 360)
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await app.addSources(urls) }
            return true
        }
        .alert(
            "Note",
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
                Text("No images loaded")
                    .font(.title2)
                Text("Pick individual images or whole folders, or drop files here.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await app.addSources(FilePicker.chooseImages()) }
                } label: {
                    Label("Choose images", systemImage: "photo")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await app.addSources(FilePicker.chooseFolders()) }
                } label: {
                    Label("Choose folders", systemImage: "folder")
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
            .onKeyPress(.delete) {
                app.removeSelected()
                return .handled
            }
            .onKeyPress(.deleteForward) {
                app.removeSelected()
                return .handled
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

    /// Fragt nach, sofern die Einstellung das verlangt.
    private func requestClear() {
        if app.preferences.confirmClear {
            showsClearConfirmation = true
        } else {
            app.clear()
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
                Text("Reading images …")
            } else {
                Text("\(app.playableItems.count) images in the slideshow")

                if !app.selection.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(app.selection.count) marked").foregroundStyle(.secondary)
                }

                // Entfernte Bilder sind unsichtbar - der Rückweg muss darum sichtbar sein.
                if app.removedCount > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(app.removedCount) removed").foregroundStyle(.secondary)
                    Button(app.showsRemoved ? "Hide" : "Show") {
                        app.showsRemoved.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    Button("Restore") { app.enableAll() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            Spacer()

            runtimeLabel
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.bar)
    }

    /// Als View statt als String: ein zusammengebauter String wird nicht übersetzt.
    @ViewBuilder
    private var runtimeLabel: some View {
        let total = Double(app.playableItems.count) * app.config.slideDuration
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60

        if total <= 0 {
            EmptyView()
        } else if minutes > 0 {
            Text("Runtime about \(minutes) min \(seconds) s")
        } else {
            Text("Runtime about \(seconds) s")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("Images …") {
                    Task { await app.addSources(FilePicker.chooseImages()) }
                }
                Button("Folders …") {
                    Task { await app.addSources(FilePicker.chooseFolders()) }
                }
                Divider()
                // Gehört zum Import und nicht zu den Wiedergabe-Einstellungen.
                Toggle("Include subfolders", isOn: $app.preferences.recursiveImport)
                Divider()
                Button("Clear list", role: .destructive) { requestClear() }
                    .disabled(app.items.isEmpty)
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add images or folders")
        }

        ToolbarItemGroup {
            if !app.items.isEmpty {
                Menu {
                    Section("Marked") {
                        Button("Mark all") { app.selectAll() }
                        Button("Clear marks") { app.clearSelection() }
                            .disabled(app.selection.isEmpty)
                    }
                    Section("Slideshow") {
                        Button("Remove marked") { app.removeSelected() }
                            .disabled(app.selection.isEmpty)
                        Button("Keep only marked") { app.keepOnlySelected() }
                            .disabled(app.selection.isEmpty)
                        Divider()
                        Button("Remove all") { app.disableAll() }
                        Button("Restore all") { app.enableAll() }
                            .disabled(app.removedCount == 0)
                        Toggle("Show removed", isOn: $app.showsRemoved)
                            .disabled(app.removedCount == 0)
                    }
                } label: {
                    Label("Selection", systemImage: "checklist")
                }
            }

            Button {
                showInspector.toggle()
            } label: {
                Label("Settings", systemImage: "sidebar.right")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                app.present()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!app.canPresent)
            .help("Start slideshow (⌘R)")
        }
    }
}
