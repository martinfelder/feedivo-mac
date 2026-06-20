import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Binding var selection: SidebarSelection?
    let onRequestAddFeed: () -> Void
    let onRequestDeleteFeed: (Feed) -> Void
    @State private var feedShowingProperties: Feed?

    var body: some View {
        List(selection: $selection) {
            Section(L10n.sidebarSmartFiltersSection) {
                ForEach(SmartFilter.allCases) { smartFilter in
                    Label {
                        Text(smartFilter.title)
                    } icon: {
                        Image(systemName: smartFilter.systemImage)
                            .foregroundStyle(smartFilter.iconColor.color)
                    }
                    .tag(SidebarSelection.smartFilter(smartFilter))
                }
            }

            Section {
                if feeds.isEmpty {
                    Text(L10n.sidebarEmptyTitle)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(feeds) { feed in
                        FeedRowView(feed: feed)
                            .tag(SidebarSelection.feed(feed.persistentModelID))
                            .contextMenu {
                                Button {
                                    feedShowingProperties = feed
                                } label: {
                                    Label(L10n.feedPropertiesCommand, systemImage: "info.circle")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    onRequestDeleteFeed(feed)
                                } label: {
                                    Label(L10n.feedDeleteCommand, systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Feedivo")
        .sheet(item: $feedShowingProperties) { feed in
            FeedPropertiesView(feed: feed)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    onRequestAddFeed()
                } label: {
                    Label(L10n.sidebarAddFeedButton, systemImage: "plus")
                }
            }
        }
    }
}

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = FeedViewModel()
    @State private var urlString = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.sidebarAddFeedTitle)
                .font(.title2)
                .fontWeight(.semibold)

            TextField(L10n.sidebarAddFeedURLPlaceholder, text: $urlString)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isLoading)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()

                Button(L10n.commonCancel) {
                    dismiss()
                }
                .disabled(viewModel.isLoading)

                Button {
                    Task {
                        await viewModel.addFeed(urlString: urlString, context: modelContext)
                        if viewModel.errorMessage == nil {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.commonAdd)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
