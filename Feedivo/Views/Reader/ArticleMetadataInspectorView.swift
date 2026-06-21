import SwiftData
import SwiftUI

struct ArticleMetadataInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \FeedFolder.name) private var folders: [FeedFolder]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var newTagName = ""

    let article: Article
    let close: () -> Void

    private var folderNames: [String] {
        FeedFolderOrganizer.folderNames(in: feeds, folders: folders)
    }

    private var folderSelection: Binding<String> {
        Binding {
            article.feed?.folderName ?? ""
        } set: { newValue in
            ArticleMetadataEditor.setFolderName(
                newValue.isEmpty ? nil : newValue,
                for: article,
                context: modelContext
            )
        }
    }

    private var sortedArticleTags: [Tag] {
        article.tags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 22) {
                folderSection
                tagSection
            }
            .padding(16)

            Spacer()
        }
        .frame(width: 300)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.readerInspectorTitle)
                    .font(.headline)

                Text(L10n.readerInspectorDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.readerInspectorFolder)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Picker(L10n.readerInspectorFolder, selection: folderSelection) {
                Text(L10n.readerInspectorNoFolder)
                    .tag("")

                ForEach(folderNames, id: \.self) { folderName in
                    Text(folderName)
                        .tag(folderName)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.readerInspectorTags)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if sortedArticleTags.isEmpty {
                Text(L10n.readerInspectorNoTags)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(sortedArticleTags) { tag in
                        tagPill(tag)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(L10n.readerInspectorAddTagPlaceholder, text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTag)

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(ArticleMetadataEditor.normalizedTagName(newTagName) == nil)
            }
        }
    }

    private func tagPill(_ tag: Tag) -> some View {
        HStack(spacing: 6) {
            Text("#\(tag.name)")
                .lineLimit(1)

            Button {
                ArticleMetadataEditor.removeTag(tag, from: article, context: modelContext)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.green)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.green.opacity(0.12), in: Capsule())
    }

    private func addTag() {
        ArticleMetadataEditor.addTag(
            named: newTagName,
            to: article,
            availableTags: tags,
            context: modelContext
        )
        newTagName = ""
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        return CGSize(
            width: width,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        for row in rows(in: bounds.width, subviews: subviews) {
            origin.x = bounds.minX
            for element in row.elements {
                element.subview.place(
                    at: origin,
                    proposal: ProposedViewSize(element.size)
                )
                origin.x += element.size.width + spacing
            }
            origin.y += row.height + spacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRow.width + size.width > width, !currentRow.elements.isEmpty {
                rows.append(currentRow)
                currentRow = Row()
            }

            currentRow.add(subview: subview, size: size, spacing: spacing)
        }

        if !currentRow.elements.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private struct Row {
        var elements: [(subview: LayoutSubview, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func add(subview: LayoutSubview, size: CGSize, spacing: CGFloat) {
            if !elements.isEmpty {
                width += spacing
            }
            elements.append((subview, size))
            width += size.width
            height = max(height, size.height)
        }
    }
}
