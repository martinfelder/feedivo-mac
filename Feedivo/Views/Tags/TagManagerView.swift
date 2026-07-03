import SwiftUI

struct TagManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    var onTagCreated: (String) -> Void = { _ in }

    @State private var tags: [TagRecord] = []
    @State private var errorMessage: String?
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.colors[0]
    @State private var tagPendingDeletion: TagRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            newTagForm
            tagList
            footer
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 420)
        .confirmationDialog(
            L10n.tagManagerDeleteTitle,
            isPresented: Binding(
                get: { tagPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        tagPendingDeletion = nil
                    }
                }
            ),
            presenting: tagPendingDeletion
        ) { tag in
            Button(L10n.tagManagerDeleteButton, role: .destructive) {
                deleteTag(tag)
                tagPendingDeletion = nil
            }
            Button(L10n.commonCancel, role: .cancel) {
                tagPendingDeletion = nil
            }
        } message: { _ in
            Text(L10n.tagManagerDeleteMessage)
        }
        .task {
            reloadTags()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tagManagerTitle)
                .font(.title2)
                .fontWeight(.semibold)
            Text(L10n.tagManagerDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var newTagForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tagManagerNewTag)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField(L10n.tagManagerNamePlaceholder, text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createTag)

                ColorSwatchPicker(selection: $newTagColorHex)

                Button(L10n.commonAdd) {
                    createTag()
                }
                .buttonStyle(.borderedProminent)
                .disabled(TagViewModel.normalizedTagName(newTagName) == nil)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var tagList: some View {
        Group {
            if tags.isEmpty {
                ContentUnavailableView(L10n.tagManagerNoTags, systemImage: "tag")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List {
                    ForEach(tags) { tag in
                        TagManagerRow(
                            tag: tag,
                            tags: tags,
                            reloadTags: reloadTags,
                            requestDelete: {
                                tagPendingDeletion = tag
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L10n.commonDone) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func createTag() {
        guard let database = feedivoDatabase else {
            errorMessage = L10n.feedPropertiesUnavailable
            return
        }

        guard let normalizedName = TagViewModel.normalizedTagName(newTagName) else {
            errorMessage = L10n.tagManagerEmptyNameError
            return
        }

        guard !containsTag(named: normalizedName, in: tags) else {
            errorMessage = L10n.tagManagerDuplicateNameError
            return
        }

        let tagID = UUID().uuidString

        do {
            try TagStore(database: database).save(
                TagRecord(
                    id: tagID,
                    name: normalizedName,
                    colorHex: TagViewModel.normalizedColorHex(newTagColorHex)
                )
            )
            SidebarBadgeInvalidation.bumpDirectTagVersion()
            newTagName = ""
            errorMessage = nil
            reloadTags()
            onTagCreated(tagID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadTags() {
        guard let database = feedivoDatabase else {
            tags = []
            errorMessage = L10n.feedPropertiesUnavailable
            return
        }

        do {
            tags = try TagStore(database: database).tags()
            errorMessage = nil
        } catch {
            tags = []
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTag(_ tag: TagRecord) {
        guard let database = feedivoDatabase else {
            errorMessage = L10n.feedPropertiesUnavailable
            return
        }

        do {
            try TagStore(database: database).deleteTag(id: tag.id)
            SidebarBadgeInvalidation.bumpDirectTagVersion()
            reloadTags()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TagManagerRow: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    let tag: TagRecord
    let tags: [TagRecord]
    let reloadTags: () -> Void
    let requestDelete: () -> Void

    @State private var draftName = ""
    @State private var rowErrorMessage: String?

    private var hasNameChanges: Bool {
        draftName != tag.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Circle()
                    .fill(TagColorPalette.color(for: tag.colorHex))
                    .frame(width: 12, height: 12)

                TextField(L10n.tagManagerNamePlaceholder, text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        draftName = tag.name
                    }
                    .onChange(of: tag.name) {
                        draftName = tag.name
                    }
                    .onChange(of: draftName) {
                        rowErrorMessage = nil
                    }

                if hasNameChanges {
                    Button {
                        saveName()
                    } label: {
                        Label(L10n.feedRenameSave, systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(TagViewModel.normalizedTagName(draftName) == nil)
                    .help(L10n.feedRenameSave)

                    Button {
                        cancelNameEdit()
                    } label: {
                        Label(L10n.commonCancel, systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.commonCancel)
                }

                ColorSwatchPicker(selection: Binding(
                    get: { tag.colorHex },
                    set: { colorHex in
                        saveColor(colorHex)
                    }
                ))

                Button(role: .destructive) {
                    requestDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if let rowErrorMessage {
                Text(rowErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
    }

    private func saveName() {
        guard let database = feedivoDatabase else {
            rowErrorMessage = L10n.feedPropertiesUnavailable
            return
        }

        guard let normalizedName = TagViewModel.normalizedTagName(draftName) else {
            rowErrorMessage = L10n.tagManagerEmptyNameError
            return
        }

        guard !containsTag(named: normalizedName, in: tags, excludingID: tag.id) else {
            rowErrorMessage = L10n.tagManagerDuplicateNameError
            return
        }

        do {
            try TagStore(database: database).renameTag(id: tag.id, name: normalizedName)
            SidebarBadgeInvalidation.bumpDirectTagVersion()
            rowErrorMessage = nil
            draftName = normalizedName
            reloadTags()
        } catch TagStore.TagStoreError.duplicateName {
            rowErrorMessage = L10n.tagManagerDuplicateNameError
        } catch {
            rowErrorMessage = error.localizedDescription
        }
    }

    private func saveColor(_ colorHex: String) {
        guard let database = feedivoDatabase else {
            rowErrorMessage = L10n.feedPropertiesUnavailable
            return
        }

        do {
            try TagStore(database: database).updateColor(id: tag.id, colorHex: colorHex)
            SidebarBadgeInvalidation.bumpDirectTagVersion()
            rowErrorMessage = nil
            reloadTags()
        } catch {
            rowErrorMessage = error.localizedDescription
        }
    }

    private func cancelNameEdit() {
        draftName = tag.name
        rowErrorMessage = nil
    }
}

private func containsTag(named name: String, in tags: [TagRecord], excludingID: String? = nil) -> Bool {
    tags.contains { tag in
        if tag.id == excludingID {
            return false
        }

        return tag.name.caseInsensitiveCompare(name) == .orderedSame
    }
}

struct ColorSwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TagColorPalette.colors, id: \.self) { colorHex in
                Button {
                    selection = colorHex
                } label: {
                    Circle()
                        .fill(TagColorPalette.color(for: colorHex))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(selection == colorHex ? Color.primary : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .help(L10n.tagManagerColor)
            }
        }
    }
}
