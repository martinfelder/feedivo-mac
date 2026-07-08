import SwiftUI

struct TagManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme

    var onTagCreated: (String) -> Void = { _ in }
    var showsDoneButton = true

    @State private var tags: [TagRecord] = []
    @State private var errorMessage: String?
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.colors[0]
    @State private var tagPendingDeletion: TagRecord?

    private var theme: RuleDialogTheme {
        RuleDialogTheme(colorScheme: colorScheme)
    }

    var body: some View {
        Group {
            if showsDoneButton {
                content
                    .padding(24)
                    .frame(width: 520)
                    .frame(minHeight: 420)
            } else {
                content
            }
        }
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            OrganizerSectionHeader(
                title: L10n.tagManagerTitle,
                description: L10n.tagManagerDescription
            )

            newTagForm

            tagList

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if showsDoneButton {
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var newTagForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tagManagerNewTag)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(theme.text2)

            FlowLayout(spacing: 10) {
                RuleDialogTextField(
                    placeholder: L10n.tagManagerNamePlaceholder,
                    text: $newTagName,
                    theme: theme
                )
                .frame(maxWidth: 300)

                HStack(spacing: 9) {
                    ForEach(TagColorPalette.colors, id: \.self) { colorHex in
                        Button {
                            newTagColorHex = colorHex
                        } label: {
                            RuleColorSwatch(
                                colorHex: colorHex,
                                isSelected: newTagColorHex == colorHex,
                                theme: theme,
                                diameter: 24
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                RuleDialogButton(
                    titleKey: L10n.commonAdd,
                    style: .primary,
                    theme: theme
                ) {
                    createTag()
                }
                .disabled(TagViewModel.normalizedTagName(newTagName) == nil)
                .opacity(TagViewModel.normalizedTagName(newTagName) == nil ? 0.4 : 1)
            }
        }
    }

    private var tagList: some View {
        Group {
            if tags.isEmpty {
                ContentUnavailableView(L10n.tagManagerNoTags, systemImage: "tag")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tags) { tag in
                        TagManagerRow(
                            tag: tag,
                            tags: tags,
                            theme: theme,
                            reloadTags: reloadTags,
                            requestDelete: {
                                tagPendingDeletion = tag
                            }
                        )
                    }
                }
                .padding(.top, 4)
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
            if showsDoneButton {
                dismiss()
            }
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
    let theme: RuleDialogTheme
    let reloadTags: () -> Void
    let requestDelete: () -> Void

    @State private var draftName = ""
    @State private var rowErrorMessage: String?

    private var hasNameChanges: Bool {
        draftName != tag.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 10) {
                Circle()
                    .fill(TagColorPalette.color(for: tag.colorHex))
                    .frame(width: 14, height: 14)

                RuleDialogTextField(
                    placeholder: L10n.tagManagerNamePlaceholder,
                    text: $draftName,
                    theme: theme
                )
                .frame(maxWidth: 300)
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(TagViewModel.normalizedTagName(draftName) == nil)
                    .help(L10n.feedRenameSave)

                    Button {
                        cancelNameEdit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.text2)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.commonCancel)
                }

                HStack(spacing: 9) {
                    ForEach(TagColorPalette.colors, id: \.self) { colorHex in
                        Button {
                            saveColor(colorHex)
                        } label: {
                            RuleColorSwatch(
                                colorHex: colorHex,
                                isSelected: TagViewModel.normalizedColorHex(tag.colorHex ?? "") == TagViewModel.normalizedColorHex(colorHex),
                                theme: theme,
                                diameter: 24
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(action: requestDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text2)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(L10n.tagManagerDeleteButton)
            }

            if let rowErrorMessage {
                Text(rowErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
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
