import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Shared Typen (zuvor in OPMLImportReviewView.swift)

enum OPMLImportStatusFilter: String, CaseIterable, Identifiable {
    case all
    case available
    case duplicates
    case unreachable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle Stati"
        case .available: "Neue Feeds"
        case .duplicates: "Duplikate"
        case .unreachable: "Nicht erreichbar"
        }
    }

    func filteredRows(from rows: [OPMLImportPreviewRow]) -> [OPMLImportPreviewRow] {
        switch self {
        case .all: rows
        case .available: rows.filter { $0.status == .available }
        case .duplicates: rows.filter { $0.status == .duplicate }
        case .unreachable: rows.filter { $0.status == .unreachable }
        }
    }
}

struct OPMLImportSelectionOptions: Equatable {
    var allowsDuplicates: Bool
    var allowsUnreachable: Bool

    func canImport(_ status: OPMLImportFeedStatus) -> Bool {
        switch status {
        case .available: true
        case .duplicate: allowsDuplicates
        case .unreachable: allowsUnreachable
        }
    }
}

struct OPMLImportDroppedFile {
    static func isSupported(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return fileExtension == "opml" || fileExtension == "xml"
    }

    static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8),
           let url = URL(string: string) {
            return url
        }
        return nil
    }
}

// MARK: - Konfiguration der Initial-Strings

struct OPMLImportPreviewConfiguration: Equatable {
    let initialSourceDescription: String
    let initialPreviewProgressText: String
    let initialSelectedFileName: String

    /// Default: OPML-Import-Sheet.
    static let importSheet = OPMLImportPreviewConfiguration(
        initialSourceDescription: "Wähle eine .opml- oder .xml-Datei, danach erscheint hier die Import-Vorschau.",
        initialPreviewProgressText: "Noch keine Datei ausgewählt.",
        initialSelectedFileName: "Keine OPML-Datei ausgewählt"
    )

    /// FirstRun-Wizard-Varianten der Leer-Texte.
    static let firstRun = OPMLImportPreviewConfiguration(
        initialSourceDescription: "Wähle aus, wie du deine ersten Feeds hinzufügen möchtest.",
        initialPreviewProgressText: "Noch keine Feeds geprüft.",
        initialSelectedFileName: "Keine OPML-Datei ausgewählt"
    )
}

// MARK: - Controller

/// Hält den gesamten geteilten State + Logik + Helfer für die OPML-Import-
/// Vorschau. Hat KEINE externen Abhängigkeiten als Felder: `feeds`,
/// `feedViewModel` und `modelContext` werden pro Aufruf übergeben
/// (feeds stammt aus @Query und kann sich ändern → kein Stale-Cache).
@Observable
@MainActor
final class OPMLImportPreviewController {
    // Über Binding mutierbar (Toggle/Picker/fileImporter/onDrop):
    var rows: [OPMLImportPreviewRow] = []
    var allowsDuplicates = false
    var allowsUnreachable = false
    var refreshAfterImport = true
    var statusFilter: OPMLImportStatusFilter = .all
    var newFolderName = ""
    var isFileImporterPresented = false
    var isDropTargeted = false

    // Nur-Lesen für Views, geschrieben von Controller-Methoden.
    // `selectedFileName` ist `internal(set)`, damit `reset()` es zurücksetzen
    // kann, ohne dass Views es direkt versehentlich setzen müssen (Reset war
    // zuvor in OPMLImportReviewView.resetFile dupliziert).
    internal(set) var selectedFileName: String
    internal(set) var sourceDescription: String
    internal(set) var previewProgressText: String
    var errorMessage: String?
    var resultMessage: String?
    internal(set) var isPreparingPreview = false
    internal(set) var customFolders: [String] = []

    /// Handle des aktuell laufenden Preview-Tasks. Wird vor jedem neuen Start
    /// und in `reset()` gecancelt und auf nil gesetzt — verhindert, dass zwei
    /// Tasks gleichzeitig `rows`/`sourceDescription` überschreiben.
    /// Nach natürlichem Abschluss bleibt das Handle stehen (cancel auf eine
    /// beendete Task ist ein No-Op); der nächste Start/reset bereinigt es.
    private(set) var previewTask: Task<Void, Never>?

    private let configuration: OPMLImportPreviewConfiguration

    init(configuration: OPMLImportPreviewConfiguration = .importSheet) {
        self.configuration = configuration
        self.selectedFileName = configuration.initialSelectedFileName
        self.sourceDescription = configuration.initialSourceDescription
        self.previewProgressText = configuration.initialPreviewProgressText
    }

    // MARK: Abgeleitete Properties

    var selectionOptions: OPMLImportSelectionOptions {
        OPMLImportSelectionOptions(
            allowsDuplicates: allowsDuplicates,
            allowsUnreachable: allowsUnreachable
        )
    }

    var selectedImportRows: [OPMLImportPreviewRow] {
        rows.filter { $0.isSelected && selectionOptions.canImport($0.status) }
    }

    var duplicateCount: Int {
        rows.filter { $0.status == .duplicate }.count
    }

    var unreachableCount: Int {
        rows.filter { $0.status == .unreachable }.count
    }

    var folderCount: Int {
        Set(selectedImportRows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count
    }

    var visibleRowIDs: Set<OPMLImportPreviewRow.ID> {
        Set(statusFilter.filteredRows(from: rows).map(\.id))
    }

    var visibleRowCount: Int {
        visibleRowIDs.count
    }

    // MARK: Helfer

    func trimmedFolderName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    func availableFolders(existingFeeds: [Feed]) -> [String] {
        let existingFolderNames = existingFeeds.compactMap { trimmedFolderName($0.folderName) }
        let previewFolderNames = rows.compactMap { trimmedFolderName($0.feed.folderName) }
        return Array(Set(existingFolderNames + previewFolderNames + customFolders))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Auswahl

    func selectAllImportableRows() {
        for index in rows.indices {
            guard visibleRowIDs.contains(rows[index].id) else { continue }
            rows[index].isSelected = selectionOptions.canImport(rows[index].status)
        }
    }

    func deselectVisibleRows() {
        for index in rows.indices where visibleRowIDs.contains(rows[index].id) {
            rows[index].isSelected = false
        }
    }

    /// Konsistente Auswahl-Synchronisation, wenn allowsDuplicates/Unreachable
    /// getoggelt werden: Duplikate werden auf allowsDuplicates gesetzt, nicht
    /// erreichbare auf allowsUnreachable. Zuvor in beiden Views (OPMLImport-
    /// ReviewView und FirstRunWizardView) dupliziert → hier die einzige Stelle,
    /// damit sie nicht auseinanderdriften.
    func applyToggleSelectionToRows() {
        for index in rows.indices {
            switch rows[index].status {
            case .duplicate:
                rows[index].isSelected = allowsDuplicates
            case .unreachable:
                rows[index].isSelected = allowsUnreachable
            case .available:
                continue
            }
        }
    }

    func createFolder() {
        let folderName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderName.isEmpty else { return }
        if !customFolders.contains(where: { $0.caseInsensitiveCompare(folderName) == .orderedSame }) {
            customFolders.append(folderName)
        }
        newFolderName = ""
    }

    /// Setzt den gemeinsamen State auf die Initial-Konfiguration zurück.
    /// View-spezifische Extras (selectedFileName, completionSummary, step)
    /// werden von den Views zusätzlich behandelt.
    func reset() {
        // Laufenden Preview-Task abbrechen, damit kein konkurrierender
        // Task nachfolgend den zurückgesetzten State überschreibt.
        previewTask?.cancel()
        previewTask = nil
        rows = []
        errorMessage = nil
        resultMessage = nil
        isPreparingPreview = false
        selectedFileName = configuration.initialSelectedFileName
        sourceDescription = configuration.initialSourceDescription
        previewProgressText = configuration.initialPreviewProgressText
        statusFilter = .all
        allowsDuplicates = false
        allowsUnreachable = false
        newFolderName = ""
        customFolders = []
        isFileImporterPresented = false
        isDropTargeted = false
    }

    // MARK: Async Preview-Flow

    func loadOPML(from result: Result<URL, Error>, existingFeeds: [Feed], feedViewModel: FeedViewModel) {
        // Vorherigen Preview-Task abbrechen, bevor eine neue Datei geladen wird —
        // verhindert konkurrierende Tasks am gemeinsamen State.
        previewTask?.cancel()
        let task = Task { @MainActor in
            do {
                let url = try result.get()
                let canAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if canAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                selectedFileName = url.lastPathComponent
                sourceDescription = "Datei wird gelesen..."
                previewProgressText = "OPML-Datei wird gelesen und vorbereitet."
                errorMessage = nil
                resultMessage = nil
                rows = []
                isPreparingPreview = true

                let data = try Data(contentsOf: url)
                let opmlFeeds = try OPMLService.parseFeeds(from: data)
                try Task.checkCancellation()
                sourceDescription = "\(opmlFeeds.count) Feeds erkannt. Feed-Adressen werden geprüft..."
                previewProgressText = "\(opmlFeeds.count) Feeds erkannt. Prüfung startet..."
                rows = await feedViewModel.opmlImportPreviewRows(
                    for: opmlFeeds,
                    existingFeeds: existingFeeds,
                    onProgress: { progress in
                        self.previewProgressText = progress.displayText
                        self.sourceDescription = progress.displayText
                    }
                )
                // Später Abbruch (Cancel trifft nach dem await, awaited-Funktion
                // wirft nicht) — State bereinigen wie im CancellationError-catch,
                // sonst bleibt der Datei-Picker-Button blockiert.
                guard !Task.isCancelled else {
                    isPreparingPreview = false
                    rows = []
                    return
                }
                sourceDescription = "\(rows.count) Feeds erkannt · \(Set(rows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count) Ordner · \(url.lastPathComponent)"
                previewProgressText = "Prüfung abgeschlossen."
                isPreparingPreview = false
            } catch is CancellationError {
                // Abbruch ist kein Fehler — State wird vom nachfolgenden Start
                // oder reset bereinigt; hier nur Vorschau-Indikator zurücksetzen.
                isPreparingPreview = false
                rows = []
            } catch {
                isPreparingPreview = false
                rows = []
                errorMessage = error.localizedDescription
                sourceDescription = "Die Datei konnte nicht gelesen werden."
                previewProgressText = "Die Datei konnte nicht gelesen werden."
            }
        }
        previewTask = task
    }

    /// FirstRun: Vorschau für manuell eingegebene Feed-Adresse (Einzel-Feed).
    func preparePreview(feeds: [OPMLFeed], existingFeeds: [Feed], feedViewModel: FeedViewModel, sourceText: String) {
        // Vorherigen Preview-Task abbrechen, bevor eine neue Vorschau startet.
        previewTask?.cancel()
        let task = Task { @MainActor in
            errorMessage = nil
            resultMessage = nil
            rows = []
            sourceDescription = sourceText
            previewProgressText = sourceText
            isPreparingPreview = true

            rows = await feedViewModel.opmlImportPreviewRows(
                for: feeds,
                existingFeeds: existingFeeds,
                onProgress: { progress in
                    self.previewProgressText = progress.displayText
                    self.sourceDescription = progress.displayText
                }
            )
            // Später Abbruch (Cancel trifft nach dem await, awaited-Funktion
            // wirft nicht) — State bereinigen wie im CancellationError-catch,
            // sonst bleibt der Datei-Picker-Button blockiert.
            guard !Task.isCancelled else {
                isPreparingPreview = false
                rows = []
                return
            }
            sourceDescription = "\(rows.count) Feeds geprüft."
            previewProgressText = "Prüfung abgeschlossen."
            isPreparingPreview = false
        }
        previewTask = task
    }

    /// Drop-Verarbeitung. `onValidFile` wird auf Main nach URL-Validierung
    /// gerufen (vor loadOPML) — FirstRun nutzt das, um `step = .importOPML`
    /// zu setzen; OPML übergibt nil.
    func handleDroppedFiles(
        _ providers: [NSItemProvider],
        existingFeeds: [Feed],
        feedViewModel: FeedViewModel,
        onValidFile: ((URL) -> Void)? = nil
    ) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            DispatchQueue.main.async {
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let url = OPMLImportDroppedFile.url(from: item),
                      OPMLImportDroppedFile.isSupported(url)
                else {
                    self.errorMessage = "Bitte eine OPML- oder XML-Datei ablegen."
                    return
                }
                onValidFile?(url)
                self.loadOPML(from: .success(url), existingFeeds: existingFeeds, feedViewModel: feedViewModel)
            }
        }
        return true
    }
}