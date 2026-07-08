import SwiftUI
import UniformTypeIdentifiers

struct SmartFolderSettingsView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SQLiteDataInvalidation.statusVersionKey) private var sqliteStatusVersion = 0
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey) private var directTagVersion = 0

    @State private var folders: [SmartFolderRecord] = []
    @State private var conditionsByFolderID: [String: [SmartFolderConditionRecord]] = [:]
    @State private var isCreatingFolder = false
    @State private var folderEditing: SmartFolderRecord?
    @State private var folderPendingDeletion: SmartFolderRecord?
    @State private var draggedFolderID: String?
    @State private var matchingCounts: [String: Int] = [:]

    private var theme: RuleDialogTheme {
        RuleDialogTheme(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if orderedFolders.isEmpty {
                ContentUnavailableView(L10n.sidebarSmartFoldersEmpty, systemImage: "folder.badge.gearshape")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                folderList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isCreatingFolder) {
            SmartFolderEditorView(existingFolders: folders)
        }
        .sheet(item: $folderEditing) { folder in
            SmartFolderEditorView(folder: folder, existingFolders: folders)
        }
        .confirmationDialog(
            L10n.sidebarSmartFolderDelete,
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        folderPendingDeletion = nil
                    }
                }
            ),
            presenting: folderPendingDeletion
        ) { folder in
            Button(L10n.commonDelete, role: .destructive) {
                delete(folder)
                folderPendingDeletion = nil
            }
            Button(L10n.commonCancel, role: .cancel) {
                folderPendingDeletion = nil
            }
        }
        .task(id: folderReloadToken) {
            loadFolders()
        }
        .task(id: countReloadToken) {
            loadMatchingCounts()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.smartFolderSettingsTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.text)

                Text(L10n.smartFolderSettingsDescription)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RuleDialogButton(
                titleKey: L10n.smartFolderRestoreDefaults,
                style: .secondary,
                theme: theme,
                systemImage: "arrow.clockwise"
            ) {
                restoreDefaultFolders()
            }

            RuleDialogButton(
                titleKey: L10n.smartFolderNewFolder,
                style: .primary,
                theme: theme,
                systemImage: "plus"
            ) {
                isCreatingFolder = true
            }
        }
    }

    private var folderList: some View {
        VStack(spacing: 0) {
            SmartFolderSettingsListHeader(theme: theme)

            ForEach(Array(orderedFolders.enumerated()), id: \.element.id) { index, folder in
                SmartFolderSettingsRow(
                    folder: folder,
                    conditions: conditionsByFolderID[folder.id] ?? [],
                    matchingArticleCount: matchingCounts[folder.id] ?? 0,
                    isDragged: draggedFolderID == folder.id,
                    theme: theme,
                    toggleSidebarVisibility: { isShown in
                        updateSidebarVisibility(folder, isShownInSidebar: isShown)
                    },
                    edit: { folderEditing = folder },
                    duplicate: { duplicate(folder) },
                    delete: { folderPendingDeletion = folder }
                )
                .onDrag {
                    draggedFolderID = folder.id
                    return NSItemProvider(object: folder.id as NSString)
                } preview: {
                    SmartFolderDragPreview(folder: folder)
                }
                .onDrop(
                    of: [.text],
                    delegate: SmartFolderRowDropDelegate(
                        targetFolder: folder,
                        orderedFolders: orderedFolders,
                        draggedFolderID: $draggedFolderID,
                        move: moveFolder
                    )
                )

                if index < orderedFolders.count - 1 {
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var countReloadToken: String {
        let folderToken = orderedFolders.map { folder in
            let conditionToken = (conditionsByFolderID[folder.id] ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { "\($0.field):\($0.conditionOperator):\($0.value):\($0.sortOrder)" }
                .joined(separator: "|")
            return "\(folder.id):\(folder.matchMode):\(conditionToken)"
        }
        .joined(separator: "#")

        return "\(folderToken)#\(sqliteStatusVersion)#\(directTagVersion)"
    }

    private var folderReloadToken: String {
        "\(sqliteStatusVersion)"
    }

    private var orderedFolders: [SmartFolderRecord] {
        folders.sorted { firstFolder, secondFolder in
            if firstFolder.sortOrder != secondFolder.sortOrder {
                return firstFolder.sortOrder < secondFolder.sortOrder
            }

            return SmartFolderFormatter.displayName(for: firstFolder)
                .localizedCaseInsensitiveCompare(SmartFolderFormatter.displayName(for: secondFolder)) == .orderedAscending
        }
    }

    private func loadFolders() {
        guard let database = feedivoDatabase else {
            folders = []
            conditionsByFolderID = [:]
            return
        }

        let store = SQLiteSmartFolderStore(database: database)
        let loadedFolders = (try? store.folders()) ?? []
        var loadedConditions: [String: [SmartFolderConditionRecord]] = [:]
        for folder in loadedFolders {
            loadedConditions[folder.id] = (try? store.conditions(folderID: folder.id)) ?? []
        }

        folders = loadedFolders
        conditionsByFolderID = loadedConditions
    }

    private func loadMatchingCounts() {
        guard let database = feedivoDatabase else {
            matchingCounts = [:]
            return
        }

        var counts: [String: Int] = [:]

        for folder in orderedFolders {
            let snapshot = SQLiteSmartFolderSnapshot(
                folder: folder,
                conditions: conditionsByFolderID[folder.id] ?? []
            )
            counts[folder.id] = (
                try? TimelineStore(database: database).count(
                    scope: .smartFolder(snapshot),
                    includeRead: true,
                    includeHidden: snapshot.includesHiddenArticles
                )
            ) ?? 0
        }

        matchingCounts = counts
    }

    private func duplicate(_ folder: SmartFolderRecord) {
        guard let database = feedivoDatabase else {
            return
        }

        _ = try? SQLiteSmartFolderStore(database: database).duplicate(
            id: folder.id,
            copyName: "\(SmartFolderFormatter.displayName(for: folder)) Kopie"
        )
        SQLiteDataInvalidation.bumpStatusVersion()
        loadFolders()
    }

    private func updateSidebarVisibility(_ folder: SmartFolderRecord, isShownInSidebar: Bool) {
        guard let database = feedivoDatabase else {
            return
        }

        try? SQLiteSmartFolderStore(database: database).updateSidebarVisibility(
            id: folder.id,
            isShownInSidebar: isShownInSidebar
        )
        SQLiteDataInvalidation.bumpStatusVersion()
        loadFolders()
    }

    private func delete(_ folder: SmartFolderRecord) {
        guard let database = feedivoDatabase else {
            return
        }

        try? SQLiteSmartFolderStore(database: database).delete(id: folder.id)
        SQLiteDataInvalidation.bumpStatusVersion()
        loadFolders()
    }

    private func restoreDefaultFolders() {
        guard let database = feedivoDatabase else {
            return
        }

        try? SQLiteSmartFolderStore(database: database).restoreDefaultFolders()
        SQLiteDataInvalidation.bumpStatusVersion()
        loadFolders()
    }

    private func moveFolder(_ sourceID: String, _ targetID: String) {
        guard let database = feedivoDatabase else {
            return
        }

        try? SQLiteSmartFolderStore(database: database).move(id: sourceID, toPositionOf: targetID)
        SQLiteDataInvalidation.bumpStatusVersion()
        loadFolders()
    }
}

private struct SmartFolderSettingsListHeader: View {
    let theme: RuleDialogTheme

    var body: some View {
        HStack(spacing: 14) {
            Text(L10n.smartFolderListHeaderOrder)
                .frame(width: 58, alignment: .leading)
            Text(L10n.smartFolderListHeaderSidebar)
                .frame(width: 66, alignment: .leading)
            Text(L10n.smartFolderListHeaderName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.smartFolderListHeaderConditions)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.smartFolderListHeaderMatches)
                .frame(width: 74, alignment: .trailing)
            Text("")
                .frame(width: 70)
        }
        .font(.system(size: 11, weight: .bold))
        .tracking(0.4)
        .textCase(.uppercase)
        .foregroundStyle(theme.text2)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(theme.card)
    }
}

private struct SmartFolderRowDropDelegate: DropDelegate {
    let targetFolder: SmartFolderRecord
    let orderedFolders: [SmartFolderRecord]
    @Binding var draggedFolderID: String?
    let move: (String, String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedFolderID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggedFolderID,
              draggedFolderID != targetFolder.id,
              orderedFolders.contains(where: { $0.id == draggedFolderID })
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            move(draggedFolderID, targetFolder.id)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedFolderID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

private struct SmartFolderSettingsRow: View {
    let folder: SmartFolderRecord
    let conditions: [SmartFolderConditionRecord]
    let matchingArticleCount: Int
    let isDragged: Bool
    let theme: RuleDialogTheme
    let toggleSidebarVisibility: (Bool) -> Void
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            dragHandle

            Button {
                toggleSidebarVisibility(!folder.isShownInSidebar)
            } label: {
                RuleDialogCheckbox(isOn: folder.isShownInSidebar, theme: theme)
            }
            .buttonStyle(.plain)
            .help(L10n.smartFolderShowInSidebar)
            .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: SmartFolderFormatter.systemImage(for: folder))
                        .foregroundStyle(SmartFolderFormatter.color(for: folder))
                        .frame(width: 18)

                    Text(SmartFolderFormatter.displayName(for: folder))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                }

                Text(folder.defaultKey != nil ? L10n.smartFolderStandardFolder : L10n.smartFolderCustomFolder)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(SmartFolderFormatter.conditionSummary(for: folder, conditions: conditions))
                .font(.system(size: 12.5))
                .foregroundStyle(theme.text2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(matchingArticleCount)")
                .font(.system(size: 13.5).monospacedDigit())
                .foregroundStyle(theme.text2)
                .frame(width: 74, alignment: .trailing)

            HStack(spacing: 6) {
                Button(action: edit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text2)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(L10n.ruleEditButton)

                Button(action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text2)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(L10n.ruleDeleteButton)
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDragged ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button(L10n.ruleEditButton, action: edit)
            Button(L10n.commonDuplicate, action: duplicate)
            Divider()
            Button(L10n.ruleDeleteButton, role: .destructive, action: delete)
        }
    }

    private var dragHandle: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(width: 58, alignment: .leading)
        .help(L10n.smartFolderDragToSort)
    }
}

private struct SmartFolderDragPreview: View {
    let folder: SmartFolderRecord

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: SmartFolderFormatter.systemImage(for: folder))
                .foregroundStyle(SmartFolderFormatter.color(for: folder))
            Text(SmartFolderFormatter.displayName(for: folder))
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
