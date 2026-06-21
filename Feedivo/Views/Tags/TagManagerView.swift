import SwiftData
import SwiftUI

struct TagManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var viewModel = TagViewModel()
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.colors[0]
    @State private var tagPendingDeletion: Tag?

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
                viewModel.deleteTag(tag, context: modelContext)
                tagPendingDeletion = nil
            }
            Button(L10n.commonCancel, role: .cancel) {
                tagPendingDeletion = nil
            }
        } message: { _ in
            Text(L10n.tagManagerDeleteMessage)
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

            if let errorMessage = viewModel.errorMessage {
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
                            viewModel: viewModel,
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
        viewModel.createTag(
            name: newTagName,
            colorHex: newTagColorHex,
            availableTags: tags,
            context: modelContext
        )

        if viewModel.errorMessage == nil {
            newTagName = ""
        }
    }
}

private struct TagManagerRow: View {
    @Environment(\.modelContext) private var modelContext

    let tag: Tag
    let tags: [Tag]
    let viewModel: TagViewModel
    let requestDelete: () -> Void

    @State private var draftName = ""

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(TagColorPalette.color(for: tag.colorHex))
                .frame(width: 12, height: 12)

            TextField(L10n.tagManagerNamePlaceholder, text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    draftName = tag.name
                }
                .onSubmit {
                    viewModel.renameTag(tag, name: draftName, availableTags: tags, context: modelContext)
                }
                .onChange(of: tag.name) {
                    draftName = tag.name
                }

            ColorSwatchPicker(selection: Binding(
                get: { tag.colorHex },
                set: { colorHex in
                    viewModel.updateColor(tag, colorHex: colorHex, context: modelContext)
                }
            ))

            Text("\(tag.articles.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(role: .destructive) {
                requestDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private struct ColorSwatchPicker: View {
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
