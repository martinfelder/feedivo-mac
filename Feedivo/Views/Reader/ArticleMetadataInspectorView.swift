import SwiftData
import SwiftUI

struct ArticleMetadataInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.interfaceTextSize) private var interfaceTextSize
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

    private var availableTagsToAdd: [Tag] {
        ArticleMetadataEditor.availableTagsToAdd(to: article, availableTags: tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 18) {
                folderSection
                tagSection
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Spacer(minLength: 0)
        }
        .frame(minWidth: 280, idealWidth: 318, maxWidth: 360)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SidebarStyle.background)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.readerInspectorTitle)
                    .font(interfaceTextSize.font(size: 15, weight: .semibold))
                    .foregroundStyle(SidebarStyle.primaryText)

                Text(L10n.readerInspectorDescription)
                    .font(interfaceTextSize.font(size: 12))
                    .fontWeight(.medium)
                    .foregroundStyle(SidebarStyle.secondaryText)
            }

            Spacer()

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(interfaceTextSize.font(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SidebarStyle.primaryText)
            .frame(
                width: interfaceTextSize.scaled(30),
                height: interfaceTextSize.scaled(30)
            )
            .background(SidebarStyle.activeSelection, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .help(L10n.readerInspectorButton)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(height: 1)
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L10n.readerInspectorFolder)

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .inspectorControl()
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(L10n.readerInspectorTags)

            if sortedArticleTags.isEmpty {
                Text(L10n.readerInspectorNoTags)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(sortedArticleTags) { tag in
                        tagPill(tag)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(L10n.readerInspectorAddTagPlaceholder, text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(interfaceTextSize.font(size: 13))
                    .padding(.horizontal, 12)
                    .frame(height: interfaceTextSize.scaled(36))
                    .inspectorControl()
                    .onSubmit(addTag)

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus")
                        .font(interfaceTextSize.font(size: 13, weight: .semibold))
                }
                .disabled(ArticleMetadataEditor.normalizedTagName(newTagName) == nil)
                .buttonStyle(.plain)
                .frame(
                    width: interfaceTextSize.scaled(36),
                    height: interfaceTextSize.scaled(36)
                )
                .background(SidebarStyle.activeSelection, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(
                    ArticleMetadataEditor.normalizedTagName(newTagName) == nil
                    ? SidebarStyle.secondaryText
                    : SidebarStyle.primaryText
                )
            }

            if !availableTagsToAdd.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(availableTagsToAdd) { tag in
                        availableTagButton(tag)
                    }
                }
            }
        }
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .textCase(.uppercase)
            .foregroundStyle(SidebarStyle.sectionText)
            .padding(.horizontal, 10)
    }

    private func tagPill(_ tag: Tag) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return HStack(spacing: 6) {
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
        .foregroundStyle(tagColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tagColor.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tagColor.opacity(0.22), lineWidth: 1)
        }
    }

    private func availableTagButton(_ tag: Tag) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Button {
            ArticleMetadataEditor.addTag(
                named: tag.name,
                to: article,
                availableTags: tags,
                context: modelContext
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption2)

                Text("#\(tag.name)")
                    .lineLimit(1)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(tagColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tagColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tagColor.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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

private extension View {
    func inspectorControl() -> some View {
        self
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SidebarStyle.separator, lineWidth: 1)
            }
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
