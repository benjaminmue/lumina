import AppKit
import UniformTypeIdentifiers

/// Dünne Hülle um NSOpenPanel für die beiden Import-Wege.
@MainActor
enum FilePicker {

    /// Variante A: einzelne Bilder auswählen (Mehrfachauswahl möglich).
    static func chooseImages() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Bilder für die Slideshow wählen"
        panel.prompt = "Auswählen"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// Variante B: einen oder mehrere Ordner auswählen.
    static func chooseFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Ordner für die Slideshow wählen"
        panel.prompt = "Auswählen"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }
}
