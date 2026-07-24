import SwiftUI

struct SmartFolderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SQLiteDataInvalidation.statusVersionKey) private var sqliteStatusVersion = 0
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey) private var directTagVersion = 0

    let folder: SmartFolderRecord?
    let existingFolders: [SmartFolderRecord]

    @State private var name = ""
    @State private var matchMode = RuleMatchMode.all
    @State private var isShownInSidebar = true
    @State private var defaultShowsReadArticles = false
    @State private var iconName = SmartFolderAppearance.defaultIconName
    @State private var colorHex = SmartFolderAppearance.defaultColorHex
    @State private var conditionDrafts = [
        SmartFolderConditionDraft(field: .title, conditionOperator: .contains, value: "")
    ]
    @State private var feedFolders: [FeedFolderRecord] = []
    @State private var previewMatchingCount = 0
    @State private var errorMessage: String?

    init(folder: SmartFolderRecord? = nil, existingFolders: [SmartFolderRecord]) {
        self.folder = folder
        self.existingFolders = existingFolders
    }

    var body: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            header(theme: theme)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
                .padding(.top, 18)
                .padding(.bottom, 18)

            nameField(theme: theme)

            sidebarCheckbox(theme: theme)
                .padding(.top, 12)

            articleVisibilityRow(theme: theme)
                .padding(.top, 12)

            appearanceCard(theme: theme)
                .padding(.top, 18)

            operatorRow(theme: theme)
                .padding(.top, 18)

            conditionsSection(theme: theme)
                .padding(.top, 18)

            previewCard(theme: theme)
                .padding(.top, 16)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.top, 10)
            }

            footer(theme: theme)
                .padding(.top, 20)
        }
        .padding(.top, 26)
        .padding(.bottom, 20)
        .padding(.horizontal, 28)
        .frame(width: 640)
        .background(theme.bg)
        .onAppear(perform: loadInitialState)
        .task(id: previewReloadToken) {
            loadPreviewMatchingCount()
        }
    }

    // MARK: - Kopfbereich

    private func header(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(folder == nil ? L10n.smartFolderEditorCreate : L10n.smartFolderEditorEdit)
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(theme.text)

            Text(L10n.smartFolderEditorDescription)
                .font(.system(size: 13.5))
                .foregroundStyle(theme.text2)
        }
    }

    // MARK: - Name

    private func nameField(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.smartFolderFieldName)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(theme.text2)

            if folder?.defaultKey != nil {
                Text(folder.map(SmartFolderFormatter.displayName) ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.input)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
            } else {
                RuleDialogTextField(
                    placeholder: L10n.smartFolderFieldNamePlaceholder,
                    text: $name,
                    theme: theme,
                    horizontalPadding: 12,
                    verticalPadding: 9,
                    fontSize: 14
                )
            }
        }
    }

    private func sidebarCheckbox(theme: RuleDialogTheme) -> some View {
        Button {
            isShownInSidebar.toggle()
        } label: {
            HStack(spacing: 9) {
                RuleDialogCheckbox(isOn: isShownInSidebar, theme: theme)

                Text(L10n.smartFolderShowInSidebar)
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.text)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
    }

    private func articleVisibilityRow(theme: RuleDialogTheme) -> some View {
        HStack(spacing: 12) {
            Text(L10n.smartFolderDefaultArticleVisibility)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text2)

            RuleSegmentedControl(
                options: [
                    (false, LocalizedStringKey(L10n.articleListReadDisplayUnreadOnly)),
                    (true, LocalizedStringKey(L10n.articleListReadDisplayAll))
                ],
                selection: $defaultShowsReadArticles,
                theme: theme
            )
        }
    }

    // MARK: - Darstellung

    private func appearanceCard(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.smartFolderAppearance)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(theme.text2)

            HStack(alignment: .center, spacing: 16) {
                iconPreview

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 12) {
                        Text(L10n.smartFolderAppearanceIcon)
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.text2)
                            .frame(width: 38, alignment: .leading)

                        SmartFolderIconPicker(selection: $iconName, theme: theme)
                    }

                    HStack(spacing: 12) {
                        Text(L10n.smartFolderAppearanceColor)
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.text2)
                            .frame(width: 38, alignment: .leading)

                        HStack(spacing: 9) {
                            ForEach(SmartFolderAppearance.colorHexValues, id: \.self) { swatchColorHex in
                                Button {
                                    colorHex = swatchColorHex
                                } label: {
                                    SmartFolderColorSwatch(
                                        colorHex: swatchColorHex,
                                        isSelected: colorHex.caseInsensitiveCompare(swatchColorHex) == .orderedSame,
                                        theme: theme
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var iconPreview: some View {
        let color = SmartFolderAppearance.color(for: colorHex)

        return ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(color.opacity(0.13))
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(color.opacity(0.33), lineWidth: 1)
            Image(systemName: iconName)
                .font(.system(size: 22))
                .foregroundStyle(color)
        }
        .frame(width: 54, height: 54)
    }

    // MARK: - Operator

    private func operatorRow(theme: RuleDialogTheme) -> some View {
        HStack(spacing: 12) {
            Text(L10n.smartFolderMatchModeOperator)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text2)

            RuleSegmentedControl(
                options: [
                    (RuleMatchMode.all, L10n.smartFolderMatchModeAll),
                    (RuleMatchMode.any, L10n.smartFolderMatchModeAny)
                ],
                selection: $matchMode,
                theme: theme
            )
        }
    }

    // MARK: - Bedingungen

    private func conditionsSection(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L10n.smartFolderConditions)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(theme.text2)

            VStack(spacing: 9) {
                ForEach(Array(conditionDrafts.enumerated()), id: \.element.id) { index, draft in
                    SmartFolderConditionRow(
                        draft: $conditionDrafts[index],
                        feedFolders: feedFolders,
                        showRemove: conditionDrafts.count > 1,
                        theme: theme,
                        onAdd: { addCondition(after: draft.id) },
                        onRemove: { removeCondition(id: draft.id) }
                    )
                }
            }
        }
    }

    // MARK: - Live-Vorschau

    private func previewCard(theme: RuleDialogTheme) -> some View {
        HStack(spacing: 11) {
            previewRing(theme: theme)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.smartFolderPreview)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(theme.text)

                Text(L10n.smartFolderPreviewMatchCount(count: previewMatchingCount))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func previewRing(theme: RuleDialogTheme) -> some View {
        ZStack {
            Circle()
                .stroke(theme.accent, lineWidth: 2)
                .frame(width: 20, height: 20)

            Circle()
                .fill(theme.accent)
                .frame(width: 4, height: 4)

            Rectangle().fill(theme.accent).frame(width: 1.5, height: 3).offset(y: -13)
            Rectangle().fill(theme.accent).frame(width: 1.5, height: 3).offset(y: 13)
            Rectangle().fill(theme.accent).frame(width: 3, height: 1.5).offset(x: -13)
            Rectangle().fill(theme.accent).frame(width: 3, height: 1.5).offset(x: 13)
        }
        .frame(width: 26, height: 26)
    }

    // MARK: - Footer

    private func footer(theme: RuleDialogTheme) -> some View {
        HStack(spacing: 10) {
            Spacer()

            Button {
                dismiss()
            } label: {
                Text(L10n.commonCancel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.card2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                save()
            } label: {
                Text(L10n.smartFolderSave)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.accent)
                    )
                    .shadow(color: theme.accent.opacity(0.45), radius: 1.5, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Zustand & Logik

    private var previewReloadToken: String {
        let conditionToken = normalizedConditionDrafts
            .map { "\($0.field.rawValue):\($0.conditionOperator.rawValue):\($0.value)" }
            .joined(separator: "|")

        return "\(name)#\(matchMode.rawValue)#\(conditionToken)#\(sqliteStatusVersion)#\(directTagVersion)"
    }

    private func loadInitialState() {
        guard let folder else {
            loadFeedFolders()
            return
        }

        name = folder.name
        matchMode = RuleMatchMode.normalized(folder.matchMode)
        isShownInSidebar = folder.isShownInSidebar
        defaultShowsReadArticles = folder.defaultShowsReadArticles
        iconName = SmartFolderAppearance.normalizedIconName(folder.iconName ?? SmartFolderAppearance.defaultIconName)
        colorHex = SmartFolderAppearance.normalizedColorHex(folder.colorHex ?? SmartFolderAppearance.defaultColorHex)

        guard let database = feedivoDatabase else {
            conditionDrafts = []
            feedFolders = []
            return
        }

        loadFeedFolders()
        let conditions = (try? SQLiteSmartFolderStore(database: database).conditions(folderID: folder.id)) ?? []
        conditionDrafts = SmartFolderFormatter.drafts(for: conditions).compactMap { draft in
            normalizeConditionFolderValue(draft)
        }

        if conditionDrafts.isEmpty {
            conditionDrafts = [
                SmartFolderConditionDraft(field: .title, conditionOperator: .contains, value: "")
            ]
        }
    }

    private func save() {
        guard let database = feedivoDatabase else {
            errorMessage = L10n.feedPropertiesUnavailable
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard folder?.defaultKey != nil || !trimmedName.isEmpty else {
            errorMessage = L10n.smartFolderErrorNameRequired
            return
        }

        let folderID = folder?.id ?? UUID().uuidString
        let sortOrder = folder?.sortOrder ?? ((existingFolders.map(\.sortOrder).max() ?? -1) + 1)
        let record = SmartFolderRecord(
            id: folderID,
            name: folder?.defaultKey == nil ? trimmedName : (folder?.name ?? trimmedName),
            matchMode: matchMode.rawValue,
            isShownInSidebar: isShownInSidebar,
            isDefault: folder?.isDefault ?? false,
            sortOrder: sortOrder,
            defaultKey: folder?.defaultKey,
            iconName: iconName,
            colorHex: colorHex,
            defaultShowsReadArticles: defaultShowsReadArticles,
            createdAt: folder?.createdAt ?? Date()
        )
        let conditions = normalizedConditionDrafts.enumerated().map { index, draft in
            SmartFolderConditionRecord(
                id: UUID().uuidString,
                smartFolderID: folderID,
                field: draft.field.rawValue,
                conditionOperator: draft.conditionOperator.rawValue,
                value: draft.value,
                sortOrder: index
            )
        }

        do {
            try SQLiteSmartFolderStore(database: database).save(record, conditions: conditions)
            SQLiteDataInvalidation.bumpStatusVersion()
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeCondition(id: UUID) {
        conditionDrafts.removeAll { $0.id == id }
    }

    private func addCondition(after id: UUID) {
        guard let index = conditionDrafts.firstIndex(where: { $0.id == id }) else {
            conditionDrafts.append(
                SmartFolderConditionDraft(field: .title, conditionOperator: .contains, value: "")
            )
            return
        }

        conditionDrafts.insert(
            SmartFolderConditionDraft(field: .title, conditionOperator: .contains, value: ""),
            at: index + 1
        )
    }

    private func loadPreviewMatchingCount() {
        guard let database = feedivoDatabase else {
            previewMatchingCount = 0
            return
        }

        let snapshot = SQLiteSmartFolderSnapshot(
            id: folder?.id ?? "preview",
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

    private func loadFeedFolders() {
        guard let database = feedivoDatabase else {
            feedFolders = []
            return
        }

        feedFolders = (try? FeedFolderStore(database: database).folders()) ?? []
    }

    private func normalizeConditionFolderValue(_ draft: SmartFolderConditionDraft) -> SmartFolderConditionDraft? {
        guard draft.field == .feedFolder else {
            return draft
        }

        guard let normalizedValue = normalizedFeedFolderValue(for: draft.value) else {
            return draft
        }

        return SmartFolderConditionDraft(
            field: draft.field,
            conditionOperator: draft.conditionOperator,
            value: normalizedValue
        )
    }

    private func normalizedConditionFolderValue(_ draft: SmartFolderConditionDraft) -> SmartFolderConditionDraft {
        guard draft.field == .feedFolder else {
            return draft
        }

        let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedValue = normalizedFeedFolderValue(for: value) {
            return SmartFolderConditionDraft(
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: normalizedValue
            )
        }

        return SmartFolderConditionDraft(
            field: draft.field,
            conditionOperator: draft.conditionOperator,
            value: value
        )
    }

    private func normalizedFeedFolderValue(for input: String) -> String? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return nil
        }

        return feedFolders.first(where: { $0.name.caseInsensitiveCompare(trimmedInput) == .orderedSame })?.name
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
                value: normalizedConditionFolderValue(
                    SmartFolderConditionDraft(
                        field: draft.field,
                        conditionOperator: draft.conditionOperator,
                        value: value
                    )
                ).value
            )
        }
    }
}

// MARK: - RuleSelectOption-Konformität (Bausteine in RuleDialogTheme.swift,
// geteilt mit dem Regel-Dialog)

extension SmartFolderConditionField: RuleSelectOption {}
extension SmartFolderConditionOperator: RuleSelectOption {}
extension SmartFolderStatusValue: RuleSelectOption {}
extension SmartFolderDateValue: RuleSelectOption {}
extension String: RuleSelectOption {}
extension Bool: RuleSelectOption {}
extension RuleMatchMode: RuleSelectOption {}

private extension SmartFolderConditionField {
    var titleKey: LocalizedStringKey { LocalizedStringKey(title) }
}

private extension SmartFolderConditionOperator {
    var titleKey: LocalizedStringKey { LocalizedStringKey(title) }
}

private extension SmartFolderStatusValue {
    var titleKey: LocalizedStringKey { LocalizedStringKey(title) }
}

private extension SmartFolderDateValue {
    var titleKey: LocalizedStringKey { LocalizedStringKey(title) }
}

// MARK: - Bedingungszeile

private struct SmartFolderConditionRow: View {
    @Binding var draft: SmartFolderConditionDraft
    let feedFolders: [FeedFolderRecord]
    let showRemove: Bool
    let theme: RuleDialogTheme
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            RuleDialogSelectMenu(
                selection: $draft.field,
                options: Array(SmartFolderConditionField.allCases),
                titleKey: { $0.titleKey },
                theme: theme
            )
            .frame(minWidth: 110)

            RuleDialogSelectMenu(
                selection: $draft.conditionOperator,
                options: Self.operators(for: draft.field),
                titleKey: { $0.titleKey },
                theme: theme
            )
            .frame(minWidth: 100)

            valueEditor
                .frame(minWidth: 120, maxWidth: .infinity)

            squareButton(symbol: "+", help: L10n.smartFolderConditionsAdd, isEnabled: true, action: onAdd)
            squareButton(symbol: "−", help: L10n.smartFolderConditionsRemove, isEnabled: showRemove, action: onRemove)
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch draft.field {
        case .status:
            RuleDialogSelectMenu(
                selection: statusBinding,
                options: Array(SmartFolderStatusValue.allCases),
                titleKey: { $0.titleKey },
                theme: theme
            )
        case .feedFolder:
            let trimmedValue = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if feedFolders.isEmpty || normalizedFeedFolderValue(for: trimmedValue) == nil {
                RuleDialogTextField(
                    placeholder: Self.valuePlaceholder(for: draft.field),
                    text: $draft.value,
                    theme: theme
                )
            } else {
                RuleDialogSelectMenu(
                    selection: feedFolderBinding,
                    options: feedFolders.map(\.name),
                    titleKey: { LocalizedStringKey($0) },
                    theme: theme
                )
            }
        case .date where draft.conditionOperator != .olderThanDays:
            RuleDialogSelectMenu(
                selection: dateBinding,
                options: Array(SmartFolderDateValue.allCases),
                titleKey: { $0.titleKey },
                theme: theme
            )
        default:
            RuleDialogTextField(
                placeholder: Self.valuePlaceholder(for: draft.field),
                text: $draft.value,
                theme: theme
            )
        }
    }

    private func squareButton(symbol: String, help: LocalizedStringKey, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 15))
                .foregroundStyle(theme.text2)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.card2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
        .help(help)
    }

    private var statusBinding: Binding<SmartFolderStatusValue> {
        Binding(
            get: { SmartFolderStatusValue(rawValue: draft.value) ?? .unread },
            set: { draft.value = $0.rawValue }
        )
    }

    private var dateBinding: Binding<SmartFolderDateValue> {
        Binding(
            get: { SmartFolderDateValue(rawValue: draft.value) ?? .today },
            set: { draft.value = $0.rawValue }
        )
    }

    private var feedFolderBinding: Binding<String> {
        Binding(
            get: {
                let trimmedValue = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalizedFeedFolderValue(for: trimmedValue) ?? trimmedValue
            },
            set: { draft.value = $0 }
        )
    }

    private func normalizedFeedFolderValue(for input: String) -> String? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return nil
        }

        return feedFolders.first(where: { $0.name.caseInsensitiveCompare(trimmedInput) == .orderedSame })?.name
    }

    private static func operators(for field: SmartFolderConditionField) -> [SmartFolderConditionOperator] {
        switch field {
        case .date:
            [.is, .isNot, .olderThanDays]
        case .status:
            [.is, .isNot]
        case .title, .text, .author, .feedFolder, .tag, .feed:
            [.contains, .notContains, .is, .isNot, .startsWith, .endsWith]
        }
    }

    private static func valuePlaceholder(for field: SmartFolderConditionField) -> LocalizedStringKey {
        LocalizedStringKey(rawValuePlaceholder(for: field))
    }

    private static func rawValuePlaceholder(for field: SmartFolderConditionField) -> String {
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
}

// MARK: - Icon-Picker (Segmented-Schiene)

private struct SmartFolderIconPicker: View {
    @Binding var selection: String
    let theme: RuleDialogTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SmartFolderAppearance.iconNames, id: \.self) { icon in
                let isSelected = selection == icon

                Button {
                    selection = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? theme.text : theme.text2)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? theme.pill : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.black.opacity(isSelected ? 0.05 : 0), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(isSelected ? 0.14 : 0), radius: 1, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.track)
        )
        .animation(.easeInOut(duration: 0.12), value: selection)
    }
}

// MARK: - Farb-Swatch

private struct SmartFolderColorSwatch: View {
    let colorHex: String
    let isSelected: Bool
    let theme: RuleDialogTheme

    var body: some View {
        let color = SmartFolderAppearance.color(for: colorHex)

        Circle()
            .fill(color)
            .frame(width: 26, height: 26)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(isSelected ? 0 : 0.15), lineWidth: 0.5)
            )
            .overlay(
                Circle()
                    .stroke(theme.bg, lineWidth: 2)
                    .padding(-2)
                    .opacity(isSelected ? 1 : 0)
            )
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .padding(-4)
                    .opacity(isSelected ? 1 : 0)
            )
            .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
