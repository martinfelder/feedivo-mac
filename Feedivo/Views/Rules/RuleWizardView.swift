import SwiftUI

private enum RuleWizardMode: String, CaseIterable, Identifiable {
    case simple
    case power

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .simple:
            L10n.ruleWizardModeSimple
        case .power:
            L10n.ruleWizardModePower
        }
    }
}

struct RuleWizardSeed: Equatable {
    var name: String
    var conditionDrafts: [RuleConditionDraft]

    init(name: String, conditionDrafts: [RuleConditionDraft]) {
        self.name = name
        self.conditionDrafts = conditionDrafts
    }

    init(articleTitle: String, feedTitle: String) {
        let trimmedTitle = articleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let seedValue = trimmedTitle.isEmpty ? fallbackName : trimmedTitle
        let field: RuleConditionField = trimmedTitle.isEmpty ? .feedTitle : .title

        self.init(
            name: seedValue,
            conditionDrafts: [
                RuleConditionDraft(
                    field: field,
                    conditionOperator: .contains,
                    value: seedValue
                )
            ]
        )
    }

    init(snapshot: ArticleReaderSnapshot) {
        self.init(articleTitle: snapshot.title, feedTitle: snapshot.feedTitle)
    }

    init(snapshot: ArticleListSnapshot) {
        self.init(articleTitle: snapshot.title, feedTitle: snapshot.feedTitle)
    }
}

struct RuleWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.colorScheme) private var colorScheme

    let rule: RuleRecord?
    let existingRules: [RuleRecord]
    let seed: RuleWizardSeed?

    @State private var tags: [TagRecord] = []
    @State private var mode: RuleWizardMode = .simple
    @State private var name = ""
    @State private var isEnabled = true
    @State private var action = RuleAction.assignTag
    @State private var matchMode = RuleMatchMode.all
    @State private var conditionDrafts = [
        RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")
    ]
    @State private var selectedTagID: String?
    @State private var creatingTag = false
    @State private var newTagName = ""
    @State private var newTagColorHex = RuleDialogTagSwatches.colors[0]
    @State private var previewMatchingCount = 0
    @State private var ruleError: String?
    @State private var tagError: String?

    init(rule: RuleRecord? = nil, existingRules: [RuleRecord] = [], seed: RuleWizardSeed? = nil) {
        self.rule = rule
        self.existingRules = existingRules
        self.seed = seed
    }

    var body: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            header(theme: theme)
            modeAndActiveRow(theme: theme)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
                .padding(.top, 18)
                .padding(.bottom, 18)

            nameField(theme: theme)
            ifCard(theme: theme)
                .padding(.top, 18)

            Text("▾")
                .font(.system(size: 13))
                .foregroundStyle(theme.text2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 5)

            thenCard(theme: theme)

            if let ruleError {
                Text(ruleError)
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
        .frame(width: 600)
        .background(theme.bg)
        .onAppear {
            loadInitialState()
        }
        .task {
            loadTags()
        }
        .task(id: previewReloadToken) {
            await reloadPreviewCount()
        }
    }

    // MARK: - Kopfbereich

    private func header(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rule == nil ? L10n.ruleWizardCreateTitle : L10n.ruleWizardEditTitle)
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(theme.text)

            Text(L10n.ruleWizardSummaryTitle)
                .font(.system(size: 13.5))
                .foregroundStyle(theme.text2)
        }
    }

    private func modeAndActiveRow(theme: RuleDialogTheme) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                Text(L10n.ruleWizardModeTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text2)

                RuleSegmentedControl(
                    options: RuleWizardMode.allCases.map { ($0, $0.title) },
                    selection: $mode,
                    theme: theme
                )
            }

            Spacer(minLength: 12)

            HStack(spacing: 9) {
                Text(L10n.ruleEnabled)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)

                RuleSwitch(isOn: $isEnabled, theme: theme)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Name

    private func nameField(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.ruleWizardNameLabel)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(theme.text2)

            RuleDialogTextField(
                placeholder: L10n.ruleWizardNamePlaceholder,
                text: $name,
                theme: theme,
                horizontalPadding: 12,
                verticalPadding: 9,
                fontSize: 14
            )
        }
    }

    // MARK: - WENN-Karte

    private func ifCard(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                RuleDialogBadge(
                    text: L10n.ruleWizardIfBadge,
                    foreground: theme.accent,
                    background: theme.accent.opacity(0.14)
                )

                Text(L10n.ruleWizardIfDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text2)
            }

            if mode == .power {
                HStack(spacing: 10) {
                    Text(L10n.ruleWizardMatchModeLabel)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.text2)

                    RuleSegmentedControl(
                        options: RuleMatchMode.allCases.map { ($0, $0.titleKey) },
                        selection: $matchMode,
                        theme: theme
                    )
                }
                .padding(.top, 13)
            }

            VStack(spacing: 9) {
                ForEach(activeConditionDraftIDs, id: \.self) { draftID in
                    if let index = conditionDrafts.firstIndex(where: { $0.id == draftID }) {
                        RuleConditionRow(
                            draft: $conditionDrafts[index],
                            showRemove: mode == .power && conditionDrafts.count > 1,
                            theme: theme,
                            onRemove: { removeCondition(id: draftID) }
                        )
                    }
                }
            }
            .padding(.top, 13)

            if mode == .power {
                Button {
                    conditionDrafts.append(
                        RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")
                    )
                } label: {
                    (Text("+ ") + Text(L10n.ruleWizardAddCondition))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(theme.border)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(theme.accent, lineWidth: 2)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 3, height: 3)
                }

                Text(L10n.ruleWizardPreviewMatchCount(count: previewMatchingCount))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accent.opacity(0.09))
            )
            .padding(.top, 14)
        }
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

    // MARK: - DANN-Karte

    private func thenCard(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                RuleDialogBadge(
                    text: L10n.ruleWizardThenBadge,
                    foreground: RuleDialogTheme.thenBadgeText,
                    background: RuleDialogTheme.switchOn.opacity(0.16)
                )

                Text(L10n.ruleWizardThenDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text2)
            }

            RuleSegmentedControl(
                options: RuleAction.allCases.map { ($0, $0.titleKey) },
                selection: $action,
                theme: theme,
                fullWidth: true,
                trackRadius: 9
            )
            .padding(.top, 13)

            switch action {
            case .assignTag:
                tagTargetSection(theme: theme)
                    .padding(.top, 15)
            case .hideArticle:
                Text(L10n.ruleWizardHideActionHint)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text2)
                    .lineSpacing(3)
                    .padding(.top, 13)
            case .notify:
                Text(L10n.ruleWizardNotifyActionHint)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text2)
                    .lineSpacing(3)
                    .padding(.top, 13)
            }
        }
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

    private func tagTargetSection(theme: RuleDialogTheme) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L10n.ruleWizardTargetTitle)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(theme.text2)

            RuleDialogFlowLayout(spacing: 8) {
                ForEach(tags) { tag in
                    RuleTagChip(
                        tag: tag,
                        isSelected: selectedTagID == tag.id,
                        theme: theme
                    ) {
                        selectedTagID = tag.id
                        creatingTag = false
                    }
                }

                RuleNewTagChip(theme: theme) {
                    creatingTag = true
                    selectedTagID = nil
                }
            }

            if creatingTag {
                tagCreationForm(theme: theme)
            }

            if let tagError {
                Text(tagError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private func tagCreationForm(theme: RuleDialogTheme) -> some View {
        let canCreate = TagViewModel.normalizedTagName(newTagName) != nil

        return VStack(alignment: .leading, spacing: 11) {
            RuleDialogTextField(
                placeholder: L10n.ruleWizardNewTagName,
                text: $newTagName,
                theme: theme,
                horizontalPadding: 11,
                verticalPadding: 8,
                fontSize: 13.5
            )

            RuleDialogFlowLayout(spacing: 12) {
                HStack(spacing: 9) {
                    ForEach(RuleDialogTagSwatches.colors, id: \.self) { colorHex in
                        Button {
                            newTagColorHex = colorHex
                        } label: {
                            RuleColorSwatch(
                                colorHex: colorHex,
                                isSelected: newTagColorHex == colorHex,
                                theme: theme
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        cancelTagCreation()
                    } label: {
                        Text(L10n.commonCancel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .fixedSize()
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(theme.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        createTag()
                    } label: {
                        Text(L10n.ruleWizardCreateTagButton)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(canCreate ? .white : theme.text2)
                            .fixedSize()
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(canCreate ? theme.accent : theme.track)
                            )
                            .shadow(color: theme.accent.opacity(canCreate ? 0.4 : 0), radius: 1, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                }
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.card2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.top, 12)
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
                Text(L10n.ruleWizardSave)
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

    private var selectedTag: TagRecord? {
        guard let selectedTagID else {
            return nil
        }

        return tags.first { $0.id == selectedTagID }
    }

    private var activeConditionDraftIDs: [UUID] {
        let list = mode == .power ? conditionDrafts : Array(conditionDrafts.prefix(1))
        return list.map(\.id)
    }

    private var activeConditionDrafts: [RuleConditionDraft] {
        mode == .simple ? Array(conditionDrafts.prefix(1)) : conditionDrafts
    }

    private var activeMatchMode: RuleMatchMode {
        mode == .simple ? .all : matchMode
    }

    private var previewReloadToken: String {
        let conditionToken = activeConditionDrafts
            .map { draft in
                "\(draft.field.rawValue):\(draft.conditionOperator.rawValue):\(draft.value)"
            }
            .joined(separator: "|")
        return "\(activeMatchMode.rawValue)|\(conditionToken)"
    }

    private func loadInitialState() {
        if let rule {
            load(rule)
        } else if let seed {
            load(seed)
        }
    }

    private func load(_ seed: RuleWizardSeed) {
        name = seed.name
        conditionDrafts = seed.conditionDrafts.isEmpty
            ? [RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")]
            : seed.conditionDrafts
        mode = conditionDrafts.count > 1 ? .power : .simple
    }

    private func load(_ rule: RuleRecord) {
        name = rule.name
        isEnabled = rule.isEnabled
        action = RuleAction.normalized(rule.action)
        matchMode = RuleMatchMode.normalized(rule.matchMode)

        if let database = feedivoDatabase {
            let conditions = (try? SQLiteRuleStore(database: database).conditions(ruleID: rule.id)) ?? []
            conditionDrafts = RuleSettingsFormatter.conditionDrafts(for: conditions)
        }

        if conditionDrafts.isEmpty {
            conditionDrafts = [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")
            ]
        }

        selectedTagID = rule.assignTagID
        mode = conditionDrafts.count > 1 ? .power : .simple
    }

    private func removeCondition(id: UUID) {
        conditionDrafts.removeAll { $0.id == id }
    }

    private func cancelTagCreation() {
        creatingTag = false
        newTagName = ""
    }

    private func createTag() {
        guard let database = feedivoDatabase else {
            tagError = L10n.feedPropertiesUnavailable
            return
        }

        guard let normalizedName = TagViewModel.normalizedTagName(newTagName) else {
            tagError = L10n.tagManagerEmptyNameError
            return
        }

        do {
            let tag = TagRecord(
                id: UUID().uuidString,
                name: normalizedName,
                colorHex: newTagColorHex
            )
            try TagStore(database: database).save(tag)
            loadTags()
            selectedTagID = tag.id
            creatingTag = false
            newTagName = ""
            tagError = nil
        } catch TagStore.TagStoreError.duplicateName {
            tagError = L10n.tagManagerDuplicateNameError
        } catch {
            tagError = error.localizedDescription
        }
    }

    private func reloadPreviewCount() async {
        guard let database = feedivoDatabase else {
            previewMatchingCount = 0
            return
        }

        do {
            previewMatchingCount = try SQLiteRuleEvaluationStore(database: database).matchingArticleCount(
                conditionDrafts: activeConditionDrafts,
                matchMode: activeMatchMode
            )
        } catch {
            previewMatchingCount = 0
        }
    }

    private func save() {
        guard let database = feedivoDatabase else {
            ruleError = L10n.feedPropertiesUnavailable
            return
        }

        let drafts = mode == .simple ? Array(conditionDrafts.prefix(1)) : conditionDrafts
        let normalizedDrafts = drafts.compactMap { draft -> RuleConditionDraft? in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return RuleConditionDraft(
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: value
            )
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !normalizedDrafts.isEmpty,
              action != .assignTag || selectedTag != nil
        else {
            ruleError = L10n.ruleValidationError
            return
        }

        let ruleID = rule?.id ?? UUID().uuidString
        let sortOrder = rule?.sortOrder ?? ((existingRules.map(\.sortOrder).max() ?? -1) + 1)
        let record = RuleRecord(
            id: ruleID,
            name: trimmedName,
            isEnabled: isEnabled,
            matchMode: activeMatchMode.rawValue,
            action: action.rawValue,
            assignTagID: action == .assignTag ? selectedTagID : nil,
            notificationTemplate: rule?.notificationTemplate ?? "{Titel}",
            notificationPriority: rule?.notificationPriority ?? RuleNotificationPriority.normal.rawValue,
            sortOrder: sortOrder,
            createdAt: rule?.createdAt ?? Date()
        )
        let conditions = normalizedDrafts.enumerated().map { index, draft in
            RuleConditionRecord(
                id: UUID().uuidString,
                ruleID: ruleID,
                field: draft.field.rawValue,
                conditionOperator: draft.conditionOperator.rawValue,
                value: draft.value,
                sortOrder: index
            )
        }

        do {
            try SQLiteRuleStore(database: database).save(record, conditions: conditions)
            ruleError = nil
            dismiss()
        } catch {
            ruleError = error.localizedDescription
        }
    }

    private func loadTags() {
        guard let database = feedivoDatabase else {
            tags = []
            return
        }

        tags = (try? TagStore(database: database).tags()) ?? []
    }
}

// MARK: - Farb-Swatches für die Tag-Erstellung im Regel-Dialog

private enum RuleDialogTagSwatches {
    static let colors = [
        "#0A84FF",
        "#30D158",
        "#FF9F0A",
        "#FF453A",
        "#BF5AF2",
        "#14B8A6",
        "#64748B"
    ]
}

// MARK: - Segmented Control (macOS-Stil, weiße Pille)

private protocol RuleSelectOption: Hashable {}
extension RuleWizardMode: RuleSelectOption {}
extension RuleMatchMode: RuleSelectOption {}
extension RuleAction: RuleSelectOption {}

private struct RuleSegmentedControl<Option: RuleSelectOption>: View {
    let options: [(Option, LocalizedStringKey)]
    @Binding var selection: Option
    let theme: RuleDialogTheme
    var fullWidth = false
    var trackRadius: CGFloat = 8

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.0 == selection

                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? theme.text : theme.text2)
                        .padding(.horizontal, fullWidth ? 6 : 15)
                        .padding(.vertical, fullWidth ? 7 : 5)
                        .frame(maxWidth: fullWidth ? .infinity : nil)
                        .multilineTextAlignment(.center)
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
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .fill(theme.track)
        )
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

// MARK: - Switch

private struct RuleSwitch: View {
    @Binding var isOn: Bool
    let theme: RuleDialogTheme

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? RuleDialogTheme.switchOn : theme.track)

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .padding(2)
            }
            .frame(width: 38, height: 23)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badge (WENN/DANN)

private struct RuleDialogBadge: View {
    let text: LocalizedStringKey
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background)
            )
    }
}

// MARK: - Text-Input im Dialog-Stil

private struct RuleDialogTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let theme: RuleDialogTheme
    var horizontalPadding: CGFloat = 11
    var verticalPadding: CGFloat = 8
    var fontSize: CGFloat = 13

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize))
            .foregroundStyle(theme.text)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Auswahl-Menü (Feld/Operator) im Dialog-Stil

private struct RuleDialogSelectMenu<Option: CaseIterable & Hashable & RuleSelectOption>: View where Option.AllCases: RandomAccessCollection {
    @Binding var selection: Option
    let titleKey: (Option) -> LocalizedStringKey
    let theme: RuleDialogTheme
    @State private var isExpanded = false

    var body: some View {
        Button {
            isExpanded = true
        } label: {
            HStack(spacing: 4) {
                Text(titleKey(selection))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("▾")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.text2)
            }
            .padding(.leading, 11)
            .padding(.trailing, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        // Eigenes Popover statt `Menu`/`Picker`: macOS erzwingt seit der
        // "Liquid Glass"-Systemoptik bei sichtbaren Menu-Controls immer die
        // native Pillen-Chrome (auch mit `.menuStyle(.borderlessButton)`),
        // und ein unsichtbarer Picker als Klick-Ziel im Hintergrund hat sein
        // eigenes AppKit-Hit-Testing, das die per SwiftUI gesetzte Frame-Größe
        // nicht übernimmt. Ein selbst gezeichnetes Popover umgeht beides.
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Option.allCases), id: \.self) { option in
                    Button {
                        selection = option
                        isExpanded = false
                    } label: {
                        Text(titleKey(option))
                            .font(.system(size: 13))
                            .foregroundStyle(theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                option == selection ? theme.card : Color.clear
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .frame(minWidth: 150)
            .background(theme.card2)
        }
    }
}

extension RuleConditionField: RuleSelectOption {}
extension RuleConditionOperator: RuleSelectOption {}

// MARK: - Bedingungszeile

private struct RuleConditionRow: View {
    @Binding var draft: RuleConditionDraft
    let showRemove: Bool
    let theme: RuleDialogTheme
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            RuleDialogSelectMenu(
                selection: $draft.field,
                titleKey: { $0.titleKey },
                theme: theme
            )
            .frame(minWidth: 110)

            RuleDialogSelectMenu(
                selection: $draft.conditionOperator,
                titleKey: { $0.titleKey },
                theme: theme
            )
            .frame(minWidth: 110)

            RuleDialogTextField(
                placeholder: L10n.ruleWizardValuePlaceholder,
                text: $draft.value,
                theme: theme
            )
            .frame(minWidth: 130, maxWidth: .infinity)

            if showRemove {
                Button(action: onRemove) {
                    Text("×")
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
                .help(L10n.ruleWizardRemoveCondition)
            }
        }
    }
}

// MARK: - Tag-Chip

private struct RuleTagChip: View {
    let tag: TagRecord
    let isSelected: Bool
    let theme: RuleDialogTheme
    let action: () -> Void

    var body: some View {
        let color = TagColorPalette.color(for: tag.colorHex)

        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)

                Text(tag.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                if isSelected {
                    Text("✓")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.text)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.13) : theme.card2)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? color.opacity(0.6) : theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RuleNewTagChip: View {
    let theme: RuleDialogTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.ruleWizardNewTagButton)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    Capsule()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(theme.border)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Farb-Swatch (Tag-Erstellung)

private struct RuleColorSwatch: View {
    let colorHex: String
    let isSelected: Bool
    let theme: RuleDialogTheme

    var body: some View {
        let color = TagColorPalette.color(for: colorHex)

        ZStack {
            if isSelected {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 30, height: 30)
                Circle()
                    .stroke(theme.bg, lineWidth: 2)
                    .frame(width: 26, height: 26)
            }

            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
        }
        .frame(width: 30, height: 30)
    }
}

// MARK: - Einfaches Flow-Layout für umbrechende Zeilen (Bedingungen, Tag-Chips)

private struct RuleDialogFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)

        return CGSize(width: proposal.width ?? totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
