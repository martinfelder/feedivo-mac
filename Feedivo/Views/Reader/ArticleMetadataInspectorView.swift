import SwiftUI

/// SQLite-Inspector für den produktiven SQLite-Reader.
/// Lädt Daten über `TagStore` statt SwiftData-Relationships.
struct ArticleMetadataInspectorView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let snapshot: ArticleReaderSnapshot
    let close: () -> Void

    @State private var assignedTags: [TagRecord] = []
    @State private var availableTags: [TagRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    metadataSection
                    tagSection
                }
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 280, idealWidth: 318, maxWidth: 360)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.94, green: 0.95, blue: 0.96))
        .task {
            loadTags()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.readerInspectorTitle)
                    .font(interfaceTextSize.font(size: 11, weight: .bold))
                    .foregroundStyle(SidebarStyle.sectionText)

                Text(snapshot.title)
                    .font(interfaceTextSize.font(size: 15, weight: .semibold))
                    .lineLimit(3)
                    .foregroundStyle(SidebarStyle.primaryText)

                Text(snapshot.feedTitle)
                    .font(interfaceTextSize.font(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
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
            .frame(width: interfaceTextSize.scaled(30), height: interfaceTextSize.scaled(30))
            .background(SidebarStyle.activeSelection, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .help(L10n.readerInspectorButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(height: 1)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            readerStatusLine(
                title: L10n.readerInspectorReadStatus,
                isActive: snapshot.isRead,
                iconActive: "checkmark.circle.fill",
                iconInactive: "circle",
                activeColor: .green,
                inactiveColor: SidebarStyle.secondaryText
            )

            readerStatusLine(
                title: L10n.readerInspectorStarStatus,
                isActive: snapshot.isStarred,
                iconActive: "star.fill",
                iconInactive: "star",
                activeColor: .yellow,
                inactiveColor: SidebarStyle.secondaryText
            )

            if let publishedAt = snapshot.publishedAt {
                HStack(spacing: 6) {
                    Text(L10n.readerInspectorPublished)
                        .font(interfaceTextSize.font(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(publishedAt.feedivoRelativeDisplay)
                        .font(interfaceTextSize.font(size: 11))
                        .foregroundStyle(SidebarStyle.primaryText)

                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 16)
    }

    private func readerStatusLine(
        title: LocalizedStringKey,
        isActive: Bool,
        iconActive: String,
        iconInactive: String,
        activeColor: Color,
        inactiveColor: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? iconActive : iconInactive)
                .foregroundStyle(isActive ? activeColor : inactiveColor)
            Text(title)
                .font(interfaceTextSize.font(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.readerInspectorTags)
                .font(interfaceTextSize.font(size: 13, weight: .semibold))
                .foregroundStyle(SidebarStyle.primaryText)
                .padding(.horizontal, 16)

            if assignedTags.isEmpty {
                Text(L10n.readerInspectorNoTags)
                    .font(interfaceTextSize.font(size: 12))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 16)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(assignedTags) { tag in
                        tagPill(tag)
                    }
                }
                .padding(.horizontal, 16)
            }

            if !availableTags.isEmpty {
                Divider()
                    .padding(.horizontal, 16)

                Text(L10n.readerInspectorNewTag)
                    .font(interfaceTextSize.font(size: 12, weight: .semibold))
                    .foregroundStyle(SidebarStyle.primaryText)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(availableTags) { tag in
                        HStack {
                            tagPill(tag)
                                .padding(.leading, 16)
                                .padding(.vertical, 4)

                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    private func tagPill(_ tag: TagRecord) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Text("#\(tag.name)")
            .lineLimit(1)
            .font(interfaceTextSize.font(size: 11.5, weight: .semibold))
            .foregroundStyle(tagColor)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(tagColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tagColor.opacity(0.24), lineWidth: 1)
            }
    }

    private func loadTags() {
        guard let database else {
            assignedTags = []
            availableTags = []
            return
        }

        do {
            let all = try TagStore(database: database).tags()
            let assigned = try TagStore(database: database).tags(articleID: snapshot.id)

            assignedTags = assigned
            availableTags = all.filter { tag in
                !assigned.contains { $0.id == tag.id }
            }
        } catch {
            assignedTags = []
            availableTags = []
        }
    }
}
