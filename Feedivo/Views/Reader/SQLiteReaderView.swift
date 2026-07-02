import SwiftUI

struct SQLiteReaderView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let articleID: String
    let canSelectPreviousArticle: Bool
    let canSelectNextArticle: Bool
    let selectPreviousArticle: () -> Void
    let selectNextArticle: () -> Void

    @State private var state = SQLiteReaderState()

    init(
        articleID: String,
        canSelectPreviousArticle: Bool = false,
        canSelectNextArticle: Bool = false,
        selectPreviousArticle: @escaping () -> Void = {},
        selectNextArticle: @escaping () -> Void = {}
    ) {
        self.articleID = articleID
        self.canSelectPreviousArticle = canSelectPreviousArticle
        self.canSelectNextArticle = canSelectNextArticle
        self.selectPreviousArticle = selectPreviousArticle
        self.selectNextArticle = selectNextArticle
    }

    var body: some View {
        Group {
            if let database {
                readerContent(database: database)
            } else {
                ContentUnavailableView(
                    "SQLite nicht verfügbar",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Die lokale Artikeldatenbank konnte nicht geöffnet werden.")
                )
            }
        }
        .navigationTitle(state.snapshot?.title ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    selectPreviousArticle()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .help(L10n.articlePreviousCommand)
                .disabled(!canSelectPreviousArticle)

                Button {
                    selectNextArticle()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .help(L10n.articleNextCommand)
                .disabled(!canSelectNextArticle)

                Button {
                    if let database {
                        state.toggleRead(database: database)
                    }
                } label: {
                    Image(systemName: state.snapshot?.isRead == true ? "circle" : "circle.fill")
                }
                .help(state.snapshot?.isRead == true ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead)
                .disabled(state.snapshot == nil)

                Button {
                    if let database {
                        state.toggleStarred(database: database)
                    }
                } label: {
                    Image(systemName: state.snapshot?.isStarred == true ? "star.fill" : "star")
                }
                .help(state.snapshot?.isStarred == true ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
                .disabled(state.snapshot == nil)

                Button {
                    if let database {
                        state.toggleArchived(database: database)
                    }
                } label: {
                    Image(systemName: state.snapshot?.isArchived == true ? "archivebox.fill" : "archivebox")
                }
                .help(L10n.articleArchiveCommand)
                .disabled(state.snapshot == nil)
            }
        }
    }

    private func readerContent(database: FeedivoDatabase) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let snapshot = state.snapshot {
                    Text(snapshot.title)
                        .font(interfaceTextSize.font(size: 30, weight: .bold))
                        .textSelection(.enabled)

                    if !state.preparedArticle.metadataText.isEmpty {
                        Text(state.preparedArticle.metadataText)
                            .font(interfaceTextSize.font(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    ForEach(state.preparedArticle.contentBlocks) { block in
                        contentBlock(block)
                    }
                } else if state.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else {
                    ContentUnavailableView(
                        "Artikel nicht gefunden",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(state.errorMessage ?? "Der Artikel ist nicht mehr in der lokalen Datenbank vorhanden.")
                    )
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
        .task(id: articleID) {
            state.load(articleID: articleID, database: database)
        }
        .id(articleID)
    }

    @ViewBuilder
    private func contentBlock(_ block: ReaderContentBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(interfaceTextSize.font(size: 17))
                .lineSpacing(5)
                .textSelection(.enabled)
        case .heading(let text):
            Text(text)
                .font(interfaceTextSize.font(size: 22, weight: .semibold))
                .padding(.top, 8)
                .textSelection(.enabled)
        case .quote(let text):
            Text(text)
                .font(interfaceTextSize.font(size: 17).italic())
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.tertiary)
                        .frame(width: 3)
                }
                .textSelection(.enabled)
        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(text)
                    .textSelection(.enabled)
            }
            .font(interfaceTextSize.font(size: 17))
        case .image(let urlString):
            CachedRemoteImageView(url: URL(string: urlString)) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(height: 180)
            }
        }
    }
}
