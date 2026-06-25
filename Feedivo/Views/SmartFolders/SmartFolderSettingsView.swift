import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SmartFolderSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SmartFolder.sortOrder) private var folders: [SmartFolder]
    @Query(sort: \Article.publishedAt, order: .reverse) private var articles: [Article]

    @State private var viewModel = SmartFolderViewModel()
    @State private var isCreatingFolder = false
    @State private var folderEditing: SmartFolder?
    @State private var folderPendingDeletion: SmartFolder?
    @State private var draggedFolderID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if orderedFolders.isEmpty {
                ContentUnavailableView("Keine intelligenten Ordner", systemImage: "folder.badge.gearshape")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                folderList
            }
        }
        .sheet(isPresented: $isCreatingFolder) {
            SmartFolderEditorView(existingFolders: folders)
        }
        .sheet(item: $folderEditing) { folder in
            SmartFolderEditorView(folder: folder, existingFolders: folders)
        }
        .confirmationDialog(
            "Intelligenten Ordner löschen",
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
            Button("Löschen", role: .destructive) {
                viewModel.deleteFolder(folder, context: modelContext)
                folderPendingDeletion = nil
            }
            Button(L10n.commonCancel, role: .cancel) {
                folderPendingDeletion = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Intelligente Ordner")
                    .font(.headline)

                Text("Dynamische Ordner werden in der Sidebar angezeigt und filtern Artikel automatisch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.restoreDefaultFolders(existingFolders: folders, context: modelContext)
            } label: {
                Label("Standardordner wiederherstellen", systemImage: "arrow.clockwise")
            }

            Button {
                isCreatingFolder = true
            } label: {
                Label("Neuer Ordner", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var folderList: some View {
        VStack(spacing: 0) {
            SmartFolderSettingsListHeader()

            ForEach(Array(orderedFolders.enumerated()), id: \.element.id) { index, folder in
                SmartFolderSettingsRow(
                    folder: folder,
                    matchingArticleCount: SmartFolderEngine.matchingArticleCount(folder: folder, articles: articles),
                    isDragged: draggedFolderID == folder.id,
                    edit: { folderEditing = folder },
                    duplicate: { duplicate(folder) },
                    delete: { folderPendingDeletion = folder }
                )
                .onDrag {
                    draggedFolderID = folder.id
                    return NSItemProvider(object: folder.id.uuidString as NSString)
                } preview: {
                    SmartFolderDragPreview(folder: folder)
                }
                .onDrop(
                    of: [.text],
                    delegate: SmartFolderRowDropDelegate(
                        targetFolder: folder,
                        orderedFolders: orderedFolders,
                        draggedFolderID: $draggedFolderID,
                        viewModel: viewModel,
                        modelContext: modelContext
                    )
                )

                if index < orderedFolders.count - 1 {
                    Divider()
                        .padding(.leading, 82)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var orderedFolders: [SmartFolder] {
        SmartFolderViewModel.sortedFolders(folders)
    }

    private func duplicate(_ folder: SmartFolder) {
        viewModel.duplicateFolder(folder, existingFolders: orderedFolders, context: modelContext)
    }
}

private struct SmartFolderSettingsListHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Reihenfolge")
                .frame(width: 58, alignment: .leading)
            Text("Sidebar")
                .frame(width: 60, alignment: .leading)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Bedingungen")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Treffer")
                .frame(width: 72, alignment: .trailing)
            Text("")
                .frame(width: 82)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct SmartFolderRowDropDelegate: DropDelegate {
    let targetFolder: SmartFolder
    let orderedFolders: [SmartFolder]
    @Binding var draggedFolderID: UUID?
    let viewModel: SmartFolderViewModel
    let modelContext: ModelContext

    func validateDrop(info: DropInfo) -> Bool {
        draggedFolderID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggedFolderID,
              draggedFolderID != targetFolder.id,
              let sourceFolder = orderedFolders.first(where: { $0.id == draggedFolderID })
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            viewModel.moveFolder(
                sourceFolder,
                toPositionOf: targetFolder,
                existingFolders: orderedFolders,
                context: modelContext
            )
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
    @Environment(\.modelContext) private var modelContext

    let folder: SmartFolder
    let matchingArticleCount: Int
    let isDragged: Bool
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            dragHandle

            Toggle("In Sidebar anzeigen", isOn: Binding(
                get: { folder.isShownInSidebar },
                set: { isShown in
                    folder.isShownInSidebar = isShown
                    try? modelContext.save()
                }
            ))
            .labelsHidden()
            .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: SmartFolderFormatter.systemImage(for: folder))
                        .foregroundStyle(SmartFolderFormatter.color(for: folder))
                        .frame(width: 18)

                    Text(folder.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }

                Text(folder.isDefault ? "Standardordner" : "Eigener Ordner")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(SmartFolderFormatter.conditionSummary(for: folder))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(matchingArticleCount)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            HStack(spacing: 6) {
                Button(action: edit) {
                    Image(systemName: "pencil")
                }
                .help(L10n.ruleEditButton)

                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .help(L10n.ruleDeleteButton)
            }
            .buttonStyle(.borderless)
            .frame(width: 82, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .opacity(isDragged ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button(L10n.ruleEditButton, action: edit)
            Button("Duplizieren", action: duplicate)
            Divider()
            Button(L10n.ruleDeleteButton, role: .destructive, action: delete)
        }
    }

    private var dragHandle: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .frame(width: 58, alignment: .leading)
        .help("Zum Sortieren ziehen")
    }
}

private struct SmartFolderDragPreview: View {
    let folder: SmartFolder

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: SmartFolderFormatter.systemImage(for: folder))
                .foregroundStyle(SmartFolderFormatter.color(for: folder))
            Text(folder.name)
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
