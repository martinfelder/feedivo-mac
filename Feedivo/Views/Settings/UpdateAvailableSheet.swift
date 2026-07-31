import SwiftUI

/// Mini-Reader-Sheet für Release-Notes eines gefundenen Updates.
/// Rendert release.bodyHTML über dieselbe ReaderContentRenderer/
/// ReaderInlineRun-Pipeline wie der Artikel-Reader (Fett/Kursiv/Links
/// funktionieren automatisch) - bewusst eine schlanke, eigene
/// Block-zu-View-Funktion statt SQLiteReaderView.contentBlock(_:)
/// wiederzuverwenden, da diese Reader-spezifisches Chrome (konfigurierbare
/// Schriftgrösse, Sticky-Header, Bild-Zoom) mitbringt, das hier nicht passt.
struct UpdateAvailableSheet: View {
    let release: GitHubRelease
    let onOpenOnGitHub: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var blocks: [ReaderContentBlock] {
        ReaderContentRenderer.blocks(summary: nil, content: release.bodyHTML, fallbackImageURL: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.updateCheckAvailableTitle(tagName: release.tagName))
                    .font(.system(size: 15, weight: .semibold))

                if let name = release.name, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ReaderContentBlockEntry.entries(from: blocks)) { entry in
                        releaseNoteBlock(entry.block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(L10n.updateCheckDismissButton) {
                    onDismiss()
                }

                Spacer()

                Button(L10n.updateCheckOpenOnGitHubButton) {
                    onOpenOnGitHub()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    @ViewBuilder
    private func releaseNoteBlock(_ block: ReaderContentBlock) -> some View {
        switch block {
        case .paragraph(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(.system(size: 13))
        case .heading(let runs):
            Text(runs.attributedString(colorScheme: colorScheme))
                .font(.system(size: 14, weight: .semibold))
        case .quote(let runs):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 3)
                Text(runs.attributedString(colorScheme: colorScheme))
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(.secondary)
            }
        case .listItem(let runs):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•")
                    .foregroundStyle(.secondary)
                Text(runs.attributedString(colorScheme: colorScheme))
                    .font(.system(size: 13))
            }
        case .image:
            // Release-Notes dieses Projekts sind reiner CHANGELOG-Text (Bullet-
            // Listen aus Commit-Nachrichten) - Bilder kommen hier praktisch nie vor,
            // bewusst nicht gerendert statt CachedRemoteImageView-Komplexität
            // für diesen einmaligen Anwendungsfall zu übernehmen.
            EmptyView()
        }
    }
}
