import SwiftData
import SwiftUI

struct SmartFolderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SQLiteDataInvalidation.statusVersionKey) private var sqliteStatusVersion = 0
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey) private var directTagVersion = 0

    let folder: SmartFolder?
    let existingFolders: [SmartFolder]

    @State private var viewModel = SmartFolderViewModel()
    @State private var name = ""
    @State private var matchMode = RuleMatchMode.all
    @State private var isShownInSidebar = true
    @State private var iconName = SmartFolderAppearance.defaultIconName
    @State private var colorHex = SmartFolderAppearance.defaultColorHex
    @State private var conditionDrafts = [
        SmartFolderConditionDraft(field: .title, conditionOperator: .contains, value: "")
    ]
    @State private var previewMatchingCount = 0

    init(folder: SmartFolder? = nil, existingFolders: [SmartFolder]) {
        self.folder = folder
        self.existingFolders = existingFolders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            basics
            appearanceEditor
            matchModePicker
            conditionsEditor
            preview
            errorMessage
            footer
        }
        .padding(24)
        .frame(width: 720)
        .onAppear(perform: loadInitialState)
        .task(id: previewReloadToken) {
            loadPreviewMatchingCount()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(folder == nil ? L10n.smartFolderEditorCreate : L10n.smartFolderEditorEdit)
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.smartFolderEditorDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Default-Ordner (defaultKey != nil) haben einen festen,
            // lokalisierten Anzeigenamen — das Name-Feld ist deaktiviert
            // und zeigt den lokalisierten Display-Namen statt des TextFields.
            if folder?.defaultKey != nil {
                Text(folder?.localizedDisplayName ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            } else {
                TextField(L10n.smartFolderFieldName, text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(L10n.smartFolderShowInSidebar, isOn: $isShownInSidebar)
        }
    }

    private var appearanceEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.smartFolderAppearance)
                .font(.headline)

            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(SmartFolderAppearance.color(for: colorHex))
                    .frame(width: 34, height: 34)
                    .background(
                        SmartFolderAppearance.color(for: colorHex).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                Picker(L10n.smartFolderAppearanceIcon, selection: $iconName) {
                    ForEach(SmartFolderAppearance.iconNames, id: \.self) { iconName in
                        Image(systemName: iconName)
                            .tag(iconName)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 6) {
                    ForEach(SmartFolderAppearance.colorHexValues, id: \.self) { swatchColorHex in
                        Button {
                            colorHex = swatchColorHex
                        } label: {
                            Circle()
                                .fill(SmartFolderAppearance.color(for: swatchColorHex))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    if colorHex == swatchColorHex {
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(swatchColorHex)
                    }
                }
            }
        }
    }

    private var matchModePicker: some View {
        Picker(L10n.smartFolderMatchModeOperator, selection: $matchMode) {
            Text(L10n.smartFolderMatchModeAll)
                .tag(RuleMatchMode.all)
            Text(L10n.smartFolderMatchModeAny)
                .tag(RuleMatchMode.any)
        }
        .pickerStyle(.segmented)
    }

    private var conditionsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.smartFolderConditions)
                .font(.headline)

            if conditionDrafts.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "tray.full")
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.smartFolderConditionsEmpty)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        addCondition()
                    } label: {
                        Label(L10n.smartFolderConditionsAdd, systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            ForEach(Array($conditionDrafts.enumerated()), id: \.element.id) { index, $draft in
                if index > 0 {
                    HStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 1)
                        Text(matchMode == .all ? L10n.smartFolderOperatorAnd : L10n.smartFolderOperatorOr)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 1)
                    }
                }

                HStack(spacing: 8) {
                    Picker("", selection: $draft.field) {
                        ForEach(SmartFolderConditionField.allCases) { field in
                            Text(field.title)
                                .tag(field)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Picker("", selection: $draft.conditionOperator) {
                        ForEach(operators(for: draft.field)) { conditionOperator in
                            Text(conditionOperator.title)
                                .tag(conditionOperator)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    valueEditor(for: $draft)

                    Button {
                        addCondition()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        removeCondition(draft)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func valueEditor(for draft: Binding<SmartFolderConditionDraft>) -> some View {
        switch draft.wrappedValue.field {
        case .status:
            Picker("", selection: draft.value) {
                ForEach(SmartFolderStatusValue.allCases) { status in
                    Text(status.title)
                        .tag(status.rawValue)
                }
            }
            .labelsHidden()
        case .date where draft.wrappedValue.conditionOperator != .olderThanDays:
            Picker("", selection: draft.value) {
                ForEach(SmartFolderDateValue.allCases) { dateValue in
                    Text(dateValue.title)
                        .tag(dateValue.rawValue)
                }
            }
            .labelsHidden()
        default:
            TextField(valuePlaceholder(for: draft.wrappedValue.field), text: draft.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "scope")
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.smartFolderPreview)
                    .font(.headline)

                Text(String.localizedStringWithFormat(String(localized: "smartFolder.preview.matches"), previewMatchingCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var previewReloadToken: String {
        let conditionToken = normalizedConditionDrafts
            .map { "\($0.field.rawValue):\($0.conditionOperator.rawValue):\($0.value)" }
            .joined(separator: "|")

        return "\(name)#\(matchMode.rawValue)#\(conditionToken)#\(sqliteStatusVersion)#\(directTagVersion)"
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button(L10n.commonCancel) {
                dismiss()
            }

            Button(L10n.smartFolderSave) {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func loadInitialState() {
        guard let folder else {
            return
        }

        name = folder.name
        matchMode = RuleMatchMode.normalized(folder.matchModeRaw)
        isShownInSidebar = folder.isShownInSidebar
        iconName = SmartFolderAppearance.normalizedIconName(folder.iconName)
        colorHex = SmartFolderAppearance.normalizedColorHex(folder.colorHex)
        let drafts = SmartFolderFormatter.drafts(for: folder)
        conditionDrafts = drafts
    }

    private func save() {
        if let folder {
            viewModel.updateFolder(
                folder,
                name: name,
                matchMode: matchMode,
                isShownInSidebar: isShownInSidebar,
                iconName: iconName,
                colorHex: colorHex,
                conditionDrafts: conditionDrafts,
                context: modelContext
            )
        } else {
            viewModel.createFolder(
                name: name,
                matchMode: matchMode,
                isShownInSidebar: isShownInSidebar,
                iconName: iconName,
                colorHex: colorHex,
                conditionDrafts: conditionDrafts,
                existingFolders: existingFolders,
                context: modelContext
            )
        }

        if viewModel.errorMessage == nil {
            dismiss()
        }
    }

    private func operators(for field: SmartFolderConditionField) -> [SmartFolderConditionOperator] {
        switch field {
        case .date:
            [.is, .isNot, .olderThanDays]
        case .title, .text, .author, .feedFolder:
            [.contains, .is, .isNot]
        case .tag, .feed, .status:
            [.is, .isNot]
        }
    }

    private func valuePlaceholder(for field: SmartFolderConditionField) -> String {
        switch field {
        case .tag:
            L10n.smartFolderPlaceholderTag
        case .feed:
            L10n.smartFolderPlaceholderFeed
        case .feedFolder:
            L10n.smartFolderPlaceholderFeedFolder
        case .date:
            L10n.smartFolderPlaceholderDate
        case .status:
            L10n.smartFolderPlaceholderStatus
        case .title:
            L10n.smartFolderPlaceholderTitle
        case .text:
            L10n.smartFolderPlaceholderText
        case .author:
            L10n.smartFolderPlaceholderAuthor
        }
    }

    private func removeCondition(_ draft: SmartFolderConditionDraft) {
        conditionDrafts.removeAll { $0.id == draft.id }
    }

    private func addCondition() {
        conditionDrafts.append(
            SmartFolderConditionDraft(field: .title, conditionOperator: .contains, value: "")
        )
    }

    private func loadPreviewMatchingCount() {
        guard let database = feedivoDatabase else {
            previewMatchingCount = 0
            return
        }

        let snapshot = SQLiteSmartFolderSnapshot(
            id: folder?.id.uuidString ?? "preview",
            name: name,
            matchMode: matchMode,
            conditionDrafts: normalizedConditionDrafts
        )

        previewMatchingCount = (
            try? TimelineStore(database: database).count(
                scope: .smartFolder(snapshot),
                includeRead: true,
                includeHidden: snapshot.includesHiddenArticles
            )
        ) ?? 0
    }

    private var normalizedConditionDrafts: [SmartFolderConditionDraft] {
        conditionDrafts.compactMap { draft in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return SmartFolderConditionDraft(
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: value
            )
        }
    }
}
