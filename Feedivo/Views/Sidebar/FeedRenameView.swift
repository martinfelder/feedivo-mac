import SwiftData
import SwiftUI

struct FeedRenameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = FeedViewModel()
    @State private var displayTitle: String

    let feed: Feed

    init(feed: Feed) {
        self.feed = feed
        _displayTitle = State(initialValue: feed.title)
    }

    private var originalTitle: String {
        let title = feed.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else {
            return feed.title
        }

        return title
    }

    private var cleanedDisplayTitle: String {
        displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !cleanedDisplayTitle.isEmpty && cleanedDisplayTitle != feed.title
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

        if cleanedDisplayTitle != feed.title {
            return L10n.feedRenameChanged
        }

        return L10n.feedRenameNoChanges
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                FeedRenameIconView(feed: feed)

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
                                displayTitle = originalTitle
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
                    viewModel.renameFeed(feed, displayTitle: displayTitle, context: modelContext)
                    if viewModel.errorMessage == nil {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding(16)
            .background(.bar)
        }
        .frame(width: 520)
    }
}

private struct FeedRenameIconView: View {
    let feed: Feed

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue.gradient)

            Text(feed.title.prefix(1).uppercased())
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
    }
}
