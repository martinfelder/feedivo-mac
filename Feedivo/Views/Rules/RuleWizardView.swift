import SwiftData
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

struct RuleWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \Rule.sortOrder) private var existingRules: [Rule]
    @Query private var articles: [Article]

    let rule: Rule?
    let sourceArticle: Article?

    @State private var viewModel = RuleViewModel()
    @State private var tagViewModel = TagViewModel()
    @State private var mode: RuleWizardMode = .simple
    @State private var name = ""
    @State private var isEnabled = true
    @State private var action = RuleAction.assignTag
    @State private var matchMode = RuleMatchMode.all
    @State private var conditionDrafts = [
        RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")
    ]
    @State private var selectedTagID: UUID?
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.colors[0]

    init(rule: Rule? = nil, sourceArticle: Article? = nil) {
        self.rule = rule
        self.sourceArticle = sourceArticle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            modePicker
            ruleBasics
            conditionsEditor
            rulePreview
            actionEditor
            targetEditor
            ruleErrorMessage
            footer
        }
        .padding(24)
        .frame(width: 640)
        .onAppear {
            loadInitialState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule == nil ? L10n.ruleWizardCreateTitle : L10n.ruleWizardEditTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.ruleWizardSummaryTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var modePicker: some View {
        Picker(L10n.ruleWizardModeTitle, selection: $mode) {
            ForEach(RuleWizardMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var ruleBasics: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.ruleWizardNamePlaceholder, text: $name)
                .textFieldStyle(.roundedBorder)

            Toggle(L10n.ruleEnabled, isOn: $isEnabled)

            if mode == .power {
                Picker(L10n.ruleWizardModeTitle, selection: $matchMode) {
                    ForEach(RuleMatchMode.allCases) { matchMode in
                        Text(matchMode.titleKey)
                            .tag(matchMode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var conditionsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.ruleWizardConditionsTitle)
                .font(.headline)

            ForEach($conditionDrafts) { $draft in
                HStack(spacing: 8) {
                    Picker("", selection: $draft.field) {
                        ForEach(RuleConditionField.allCases) { field in
                            Text(field.titleKey)
                                .tag(field)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Picker("", selection: $draft.conditionOperator) {
                        ForEach(RuleConditionOperator.allCases) { conditionOperator in
                            Text(conditionOperator.titleKey)
                                .tag(conditionOperator)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    TextField(L10n.ruleWizardValuePlaceholder, text: $draft.value)
                        .textFieldStyle(.roundedBorder)

                    if mode == .power && conditionDrafts.count > 1 {
                        Button {
                            removeCondition(draft)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.ruleWizardRemoveCondition)
                    }
                }
            }

            if mode == .power {
                Button {
                    conditionDrafts.append(
                        RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")
                    )
                } label: {
                    Label(L10n.ruleWizardAddCondition, systemImage: "plus")
                }
            }
        }
    }

    private var targetEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.ruleWizardTargetTitle)
                .font(.headline)

            Picker(L10n.ruleWizardExistingTag, selection: $selectedTagID) {
                Text(L10n.ruleWizardExistingTag)
                    .tag(Optional<UUID>.none)

                ForEach(tags) { tag in
                    Text(tag.name)
                        .tag(Optional(tag.id))
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 10) {
                TextField(L10n.ruleWizardNewTagName, text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                ColorSwatchPicker(selection: $newTagColorHex)

                Button(L10n.commonAdd) {
                    createTag()
                }
                .disabled(TagViewModel.normalizedTagName(newTagName) == nil)
            }

            if let errorMessage = tagViewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .disabled(action != .assignTag)
        .opacity(action == .assignTag ? 1 : 0.45)
    }

    private var actionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.ruleWizardActionTitle)
                .font(.headline)

            Picker(L10n.ruleWizardActionTitle, selection: $action) {
                ForEach(RuleAction.allCases) { action in
                    Text(action.titleKey)
                        .tag(action)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var ruleErrorMessage: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private var rulePreview: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: previewHasConditions ? "scope" : "exclamationmark.circle")
                .foregroundStyle(previewHasConditions ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.ruleWizardPreviewTitle)
                    .font(.headline)

                Text(previewDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button(L10n.commonCancel) {
                dismiss()
            }

            Button(L10n.ruleWizardSave) {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var selectedTag: Tag? {
        guard let selectedTagID else {
            return nil
        }

        return tags.first { $0.id == selectedTagID }
    }

    private var activeConditionDrafts: [RuleConditionDraft] {
        mode == .simple ? Array(conditionDrafts.prefix(1)) : conditionDrafts
    }

    private var activeMatchMode: RuleMatchMode {
        mode == .simple ? .all : matchMode
    }

    private var previewHasConditions: Bool {
        activeConditionDrafts.contains { draft in
            !draft.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var previewDescription: String {
        guard previewHasConditions else {
            return String(localized: "ruleWizard.preview.noConditions")
        }

        let matchingCount = RuleEngine.matchingArticleCount(
            conditionDrafts: activeConditionDrafts,
            matchMode: activeMatchMode,
            articles: articles
        )
        return L10n.ruleWizardPreviewMatchCount(count: matchingCount)
    }

    private func loadInitialState() {
        if let rule {
            load(rule)
        } else {
            loadSourceArticleIfNeeded()
        }
    }

    private func load(_ rule: Rule) {
        name = rule.name
        isEnabled = rule.isEnabled
        action = RuleAction.normalized(rule.actionRaw)
        matchMode = RuleMatchMode.normalized(rule.conditionMatchMode)
        conditionDrafts = rule.conditions
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { condition in
                guard let field = RuleConditionField(rawValue: condition.field),
                      let conditionOperator = RuleConditionOperator(rawValue: condition.conditionOperator)
                else {
                    return nil
                }

                return RuleConditionDraft(
                    field: field,
                    conditionOperator: conditionOperator,
                    value: condition.value
                )
            }

        if conditionDrafts.isEmpty {
            conditionDrafts = [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: "")
            ]
        }

        selectedTagID = rule.assignTag?.id
        mode = conditionDrafts.count > 1 ? .power : .simple
    }

    private func loadSourceArticleIfNeeded() {
        guard let sourceArticle else {
            return
        }

        if let feedTitle = sourceArticle.feed?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !feedTitle.isEmpty {
            conditionDrafts = [
                RuleConditionDraft(field: .feedTitle, conditionOperator: .contains, value: feedTitle)
            ]
            name = feedTitle
        } else {
            conditionDrafts = [
                RuleConditionDraft(field: .title, conditionOperator: .contains, value: suggestedTitleWord(from: sourceArticle.title))
            ]
            name = sourceArticle.title
        }
    }

    private func suggestedTitleWord(from title: String) -> String {
        title
            .split(separator: " ")
            .map(String.init)
            .first { $0.count >= 4 } ?? title
    }

    private func removeCondition(_ draft: RuleConditionDraft) {
        conditionDrafts.removeAll { $0.id == draft.id }
    }

    private func createTag() {
        tagViewModel.createTag(
            name: newTagName,
            colorHex: newTagColorHex,
            availableTags: tags,
            context: modelContext
        )

        if tagViewModel.errorMessage == nil {
            let normalizedName = TagViewModel.normalizedTagName(newTagName)
            selectedTagID = tags.first { $0.name == normalizedName }?.id
            newTagName = ""
        }
    }

    private func save() {
        let drafts = mode == .simple ? Array(conditionDrafts.prefix(1)) : conditionDrafts
        if let rule {
            viewModel.updateRule(
                rule,
                name: name,
                isEnabled: isEnabled,
                action: action,
                matchMode: matchMode,
                conditionDrafts: drafts,
                assignTag: selectedTag,
                context: modelContext
            )
        } else {
            viewModel.createRule(
                name: name,
                isEnabled: isEnabled,
                action: action,
                matchMode: matchMode,
                conditionDrafts: drafts,
                assignTag: selectedTag,
                existingRules: existingRules,
                context: modelContext
            )
        }

        if viewModel.errorMessage == nil {
            dismiss()
        }
    }
}
