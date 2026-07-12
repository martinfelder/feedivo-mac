import SwiftUI

struct FeedRenameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @State private var displayTitle: String = ""
    @State private var feedRecord: FeedRecord?
    @State private var errorMessage: String?

    let feedID: String

    init(feedID: String) {
        self.feedID = feedID
    }

    private var originalTitle: String {
        let title = feedRecord?.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else {
            return currentTitle
        }

        return title
    }

    private var currentTitle: String {
        feedRecord?.title ?? ""
    }

    private var cleanedDisplayTitle: String {
        displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !cleanedDisplayTitle.isEmpty && cleanedDisplayTitle != currentTitle
    }

    private var canRestoreOriginal: Bool {
        cleanedDisplayTitle != originalTitle
    }

    private var statusText: String {
        if cleanedDisplayTitle.isEmpty {
            return L10n.feedRenameEmptyName
        }

        if cleanedDisplayTitle == originalTitle {
            return L10n.feedRenameRestored
        }

        if cleanedDisplayTitle != currentTitle {
            return L10n.feedRenameChanged
        }

        return L10n.feedRenameNoChanges
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                FeedRenameIconView(faviconURL: feedRecord?.faviconURL)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.feedRenameTitle)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(L10n.feedRenameDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.feedRenameDisplayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField(L10n.feedRenameDisplayName, text: $displayTitle)
                                .textFieldStyle(.roundedBorder)

                            Button(L10n.feedRenameRestoreOriginal) {
                                restoreOriginalTitle()
                            }
                            .disabled(!canRestoreOriginal)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.feedRenameOriginalName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(L10n.feedRenameOriginalStored)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(originalTitle)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.quaternary, lineWidth: 1)
                            }
                    }

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(cleanedDisplayTitle.isEmpty ? .red : .secondary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(24)

            Divider()

            HStack {
                Spacer()

                Button(L10n.commonCancel) {
                    dismiss()
                }

                Button(L10n.feedRenameSave) {
                    saveDisplayTitle()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding(16)
            .background(.bar)
        }
        .frame(width: 520)
        .task {
            loadFeedRecord()
        }
    }

    private func loadFeedRecord() {
        guard let database = feedivoDatabase else {
            errorMessage = L10n.feedRenameDatabaseUnavailable
            return
        }

        do {
            let record = try FeedStore(database: database).feed(id: feedID)
            feedRecord = record
            displayTitle = record?.title ?? ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveDisplayTitle() {
        guard let database = feedivoDatabase else {
            errorMessage = L10n.feedRenameDatabaseUnavailable
            return
        }

        do {
            try FeedStore(database: database).renameFeed(
                id: feedID,
                displayTitle: displayTitle
            )
            SQLiteDataInvalidation.bumpStatusVersion()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreOriginalTitle() {
        guard let database = feedivoDatabase else {
            errorMessage = L10n.feedRenameDatabaseUnavailable
            return
        }

        do {
            try FeedStore(database: database).restoreOriginalTitle(id: feedID)
            SQLiteDataInvalidation.bumpStatusVersion()
            loadFeedRecord()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FeedRenameIconView: View {
    let faviconURL: String?

    var body: some View {
        Group {
            if let faviconURL,
               let url = URL(string: faviconURL) {
                CachedRemoteImageView(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } placeholder: {
                    fallbackIcon
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 52, height: 52)
        .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.title3)
            .foregroundStyle(.secondary)
    }
}