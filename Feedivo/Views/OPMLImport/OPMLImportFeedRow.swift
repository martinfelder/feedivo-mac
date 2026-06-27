import SwiftUI

/// Layout-Konfiguration der OPML-Feed-Zeile. OPML-Import-Sheet zeigt eine
/// zusätzliche „Website"-Spalte, FirstRun nicht; Höhen/Spaltenbreiten
/// unterscheiden sich leicht.
struct OPMLImportFeedRowLayout: Equatable {
    var showsWebsite: Bool
    var rowHeight: CGFloat
    var folderWidth: CGFloat
    var statusWidth: CGFloat

    static let importSheet = OPMLImportFeedRowLayout(
        showsWebsite: true, rowHeight: 58, folderWidth: 154, statusWidth: 108
    )
    static let firstRun = OPMLImportFeedRowLayout(
        showsWebsite: false, rowHeight: 42, folderWidth: 140, statusWidth: 110
    )
}

/// Einheitliche Feed-Zeile für OPML-Import-Sheet und FirstRun-Wizard.
/// Ersetzt die zuvor separaten OPMLImportFeedRow und FirstRunImportFeedRow.
struct OPMLImportFeedRow: View {
    @Binding var row: OPMLImportPreviewRow
    let selectionOptions: OPMLImportSelectionOptions
    let availableFolders: [String]
    let layout: OPMLImportFeedRowLayout

    private var isSelectable: Bool {
        selectionOptions.canImport(row.status)
    }

    // Interner Sentinel für „Ohne Ordner": leerer String statt des Display-
    // Literals. Ein realer Ordner kann nicht "" heißen (`createFolder` lehnt
    // leere Namen ab), daher kein Kollisionsrisiko wie beim alten Literal
    // „Ohne Ordner" — dort setzte die Wahl eines echten Ordners dieses Namens
    // folderName=nil (Datenverlust).
    private var folderBinding: Binding<String> {
        Binding(
            get: {
                trimmedFolderName(row.feed.folderName) ?? ""
            },
            set: { newValue in
                let folderName = newValue.isEmpty ? nil : newValue
                row.feed = OPMLFeed(
                    title: row.feed.title,
                    xmlURL: row.feed.xmlURL,
                    htmlURL: row.feed.htmlURL,
                    folderName: folderName
                )
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $row.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!isSelectable)
                .accessibilityLabel("\(row.feed.title) importieren")
                .frame(width: 34, alignment: .leading)

            feedText
                .frame(maxWidth: .infinity, alignment: .leading)

            if layout.showsWebsite {
                Text(hostName(from: row.feed.htmlURL ?? row.feed.xmlURL))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .frame(width: 180, alignment: .leading)
            }

            Picker("", selection: folderBinding) {
                Text("Ohne Ordner").tag("")
                ForEach(availableFolders, id: \.self) { folder in
                    Text(folder).tag(folder)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("Ordner für \(row.feed.title)")
            .frame(width: layout.folderWidth, alignment: .leading)

            statusBadge
                .frame(width: layout.statusWidth, alignment: .leading)
        }
        .frame(height: layout.rowHeight)
        .padding(.horizontal, 12)
        .background(rowBackground)
        .onChange(of: row.isSelected) {
            if !isSelectable {
                row.isSelected = false
            }
        }
    }

    private var feedText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.feed.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(row.feed.xmlURL)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.16)))
            .lineLimit(1)
    }

    private var rowBackground: Color {
        switch row.status {
        case .available: .clear
        case .duplicate: Color(nsColor: .controlBackgroundColor).opacity(0.74)
        case .unreachable: Color.orange.opacity(0.08)
        }
    }

    private var statusText: String {
        switch row.status {
        case .available: "Neu"
        case .duplicate: "Duplikat"
        case .unreachable: "Nicht erreichbar"
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .available: .green
        case .duplicate: .red
        case .unreachable: .orange
        }
    }

    private func hostName(from value: String) -> String {
        guard let host = URL(string: value)?.host(percentEncoded: false) else {
            return "Ungültige URL"
        }
        return host.replacing(/^www\./, with: "")
    }

    private func trimmedFolderName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}