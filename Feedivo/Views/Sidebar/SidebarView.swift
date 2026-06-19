import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Binding var selectedFeed: Feed?
    @State private var isShowingAddFeedSheet = false

    var body: some View {
        List(selection: $selectedFeed) {
            if feeds.isEmpty {
                Text(L10n.sidebarEmptyTitle)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(feeds) { feed in
                    Label(feed.title, systemImage: "dot.radiowaves.left.and.right")
                        .tag(feed)
                }
            }
        }
        .navigationTitle("Feedivo")
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingAddFeedSheet = true
                } label: {
                    Label(L10n.sidebarAddFeedButton, systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddFeedSheet) {
            AddFeedSheet()
        }
    }
}

private struct AddFeedSheet: View {
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
