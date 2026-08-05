import SwiftUI

/// Wiederverwendbarer Tag-Zuweisungs-/Erstellungs-Baustein für einen einzelnen Artikel.
/// Kapselt die TagStore-Zugriffslogik, die zuvor nur in ArticleMetadataInspectorView lag.
/// Genutzt sowohl vom Metadaten-Inspector (eingebettete Sektion) als auch vom
/// "+"-Button-Popover im Reader-Header (SQLiteReaderView) — beide Aufrufer synchronisieren
/// sich automatisch über SidebarBadgeInvalidation.directTagVersionKey.
struct ArticleTagAssignmentView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let articleID: String
    let snapshotTags: [ReaderArticleTagMetadata]

    @State private var assignedTags: [TagRecord] = []
    @State private var availableTags: [TagRecord] = []
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.defaultColorHex

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if assignedTags.isEmpty && availableTags.isEmpty {
                Text(L10n.readerInspectorNoTags)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.primaryValueFontSize))
                    .foregroundStyle(SidebarStyle.secondaryText)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(assignedTags) { tag in
                        tagTogglePill(tag, isActive: true)
                    }

                    ForEach(availableTags) { tag in
                        tagTogglePill(tag, isActive: false)
                    }
                }
            }

            tagCreator
        }
        .task(id: articleID) {
            loadTags()
        }
        .onChange(of: SidebarBadgeInvalidationSignal.shared.directTagVersion) { _, _ in
            loadTags()
        }
        .onChange(of: snapshotTags) { _, _ in
            loadTags()
        }
    }

    private var tagCreator: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L10n.readerInspectorNewTag)

            HStack(spacing: 6) {
                TextField(L10n.readerInspectorAddTagPlaceholder, text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.controlFontSize))
                    .padding(.horizontal, 9)
                    .frame(height: interfaceTextSize.scaled(30))
                    .sqliteInspectorControl()
                    .onSubmit(addTag)

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus")
                        .font(interfaceTextSize.font(size: ArticleInspectorTypography.iconFontSize, weight: .semibold))
                }
                .disabled(normalizedTagName(newTagName) == nil)
                .buttonStyle(.plain)
                .frame(width: interfaceTextSize.scaled(32), height: interfaceTextSize.scaled(30))
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(SidebarStyle.separator, lineWidth: 1)
                }
                .foregroundStyle(
                    normalizedTagName(newTagName) == nil
                    ? SidebarStyle.secondaryText
                    : SidebarStyle.primaryText
                )
            }

            ColorSwatchPicker(selection: $newTagColorHex)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(height: 1)
        }
        .padding(.top, 4)
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .bold))
            .foregroundStyle(SidebarStyle.sectionText)
    }

    private func tagTogglePill(_ tag: TagRecord, isActive: Bool) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Button {
            toggleTag(tag, isActive: isActive)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(tagColor)
                    .frame(width: 7, height: 7)

                Text(tag.name)
                    .lineLimit(1)
            }
            .font(interfaceTextSize.font(size: ArticleInspectorTypography.chipFontSize, weight: .semibold))
            .foregroundStyle(isActive ? SidebarStyle.primaryText : SidebarStyle.secondaryText)
            .padding(.horizontal, 8)
            .frame(minHeight: interfaceTextSize.scaled(26))
            .background(isActive ? tagColor.opacity(0.12) : Color(nsColor: .textBackgroundColor), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isActive ? tagColor.opacity(0.42) : SidebarStyle.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadTags() {
        guard let database else {
            assignedTags = snapshotTags.map { TagRecord(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
            availableTags = []
            return
        }

        do {
            let allTags = try TagStore(database: database).tags()
            let directlyAssignedTags = try TagStore(database: database).tags(articleID: articleID)
            assignedTags = mergedAssignedTags(directTags: directlyAssignedTags)
            availableTags = allTags.filter { tag in
                !assignedTags.contains { $0.id == tag.id }
            }
        } catch {
            assignedTags = snapshotTags.map { TagRecord(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
            availableTags = []
        }
    }

    private func mergedAssignedTags(directTags: [TagRecord]) -> [TagRecord] {
        var recordsByID: [String: TagRecord] = [:]
        for tag in snapshotTags {
            recordsByID[tag.id] = TagRecord(id: tag.id, name: tag.name, colorHex: tag.colorHex)
        }
        for tag in directTags {
            recordsByID[tag.id] = tag
        }

        return recordsByID.values.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
        }
    }

    private func toggleTag(_ tag: TagRecord, isActive: Bool) {
        guard let database else {
            return
        }

        do {
            if isActive {
                try TagStore(database: database).removeTag(tagID: tag.id, fromArticleID: articleID)
            } else {
                try TagStore(database: database).assignTag(tagID: tag.id, toArticleID: articleID, at: Date())
            }
            SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()
            loadTags()
        } catch {
            return
        }
    }

    private func addTag() {
        guard let database,
              let normalizedName = normalizedTagName(newTagName) else {
            return
        }

        do {
            let existingTag = try TagStore(database: database).tags().first {
                $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
            }
            let tag = existingTag ?? TagRecord(name: normalizedName, colorHex: newTagColorHex)
            if existingTag == nil {
                try TagStore(database: database).save(tag)
            }
            try TagStore(database: database).assignTag(tagID: tag.id, toArticleID: articleID, at: Date())
            SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()
            newTagName = ""
            loadTags()
        } catch {
            return
        }
    }

    private func normalizedTagName(_ name: String?) -> String? {
        guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty else {
            return nil
        }

        return trimmedName
    }
}
