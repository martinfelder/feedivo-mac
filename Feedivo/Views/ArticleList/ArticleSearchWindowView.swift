import SwiftUI

struct ArticleSearchWindowView: View {
    static let windowID = "article-search-window"

    @Environment(\.feedivoDatabase) private var database
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    // SQLite-Feed-Liste für das Filter-Dropdown (statt @Query [Feed]). Wird beim
    // Erscheinen und bei Status-Version-Bumps neu geladen.
    @State private var feeds: [FeedRecord] = []
    @State private var tags: [TagRecord] = []
    @State private var isTagPopoverPresented = false
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
    @AppStorage(NativeArticleListSettings.isEnabledKey)
    private var usesNativeArticleList = NativeArticleListSettings.defaultIsEnabled

    @State private var searchState = ArticleSearchWindowState()
    @State private var snapshots: [ArticleListSnapshot] = []
    @State private var loadErrorMessage: String?
    @State private var selectedResultID: String?
    @FocusState private var isResultListFocused: Bool

    /// P4: Debounced Suchtext — das TextField bleibt an `searchState.searchText`
    /// gebunden (so tippt der Nutzer flüssig), aber Filterung/Sortierung laufen
    /// erst nach einer kurzen Typ-Pause (250 ms) über den committeten Text statt
    /// bei jedem Tastendruck über alle Artikel. Picker (Feed/Tag/Datum/Status)
    /// ändern `searchState` direkt und bleiben sofort wirksam.
    @State private var debouncedSearchText: String = ""

    /// Such-State mit committetem (debounced) Text — die Filter-Picker kommen
    /// weiter live aus `searchState`, nur der Text ist debounced.
    private var committedState: ArticleSearchWindowState {
        var state = searchState
        state.searchText = debouncedSearchText
        return state
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider()

            if snapshots.isEmpty {
                emptyState
            } else {
                HSplitView {
                    resultList

                    previewPanel
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 460)
        // P4: Debounce des Suchtextes. `.task(id:)` bricht die vorherige Aufgabe
        // ab, sobald sich der Text ändert — committet nur nach 250 ms ohne
        // weiteren Tastendruck. Leeres Feld wird sofort committet (kein Lag beim
        // Löschen/Freimachen).
        .task(id: searchState.searchText) {
            if searchState.searchText.isEmpty {
                debouncedSearchText = ""
                return
            }
            guard await SearchDebounce.wait() else {
                return
            }
            debouncedSearchText = searchState.searchText
        }
        .task(id: searchLoadToken) {
            loadSnapshots()
        }
        .task(id: sqliteStatusVersion) {
            loadFeeds()
            loadTags()
        }
    }

    private var searchHeader: some View {
        let theme = RuleDialogTheme(colorScheme: colorScheme)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(L10n.articleSearchPlaceholder, text: $searchState.searchText)
                    .textFieldStyle(.plain)

                if !searchState.searchText.isEmpty || searchState.query.filters.isActive {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(L10n.articleSearchClear)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(theme.border, lineWidth: 1)
            }

            HStack(spacing: 8) {
                searchFieldPicker
                searchFeedPicker
                searchTagPicker
                searchDatePicker
                searchStatusPicker
                Spacer(minLength: 0)

                Text(L10n.articleSearchMatchCount(snapshots.count))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accent.opacity(0.13), in: Capsule())
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(theme.card)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var searchFieldPicker: some View {
        Picker("", selection: $searchState.field) {
            ForEach(ArticleSearchField.allCases) { field in
                Text(label(for: field)).tag(field)
            }
        }
        .labelsHidden()
        .frame(width: 130)
    }

    private var searchFeedPicker: some View {
        Picker("", selection: $searchState.feedID) {
            Text(L10n.articleSearchFeedAll).tag(UUID?.none)

            ForEach(feeds) { feed in
                Text(feed.title).tag(UUID(uuidString: feed.id))
            }
        }
        .labelsHidden()
        .frame(width: 150)
    }

    private var searchTagPicker: some View {
        Button {
            isTagPopoverPresented.toggle()
        } label: {
            Text(tagButtonLabel)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 136)
        .popover(isPresented: $isTagPopoverPresented) {
            tagPopoverContent
        }
    }

    private var tagButtonLabel: String {
        searchState.tagIDs.isEmpty
            ? L10n.articleSearchTagsButtonLabel
            : "\(L10n.articleSearchTagsButtonLabel) (\(searchState.tagIDs.count))"
    }

    private var tagPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $searchState.tagMatchMode) {
                Text(L10n.articleSearchTagMatchModeAny).tag(ArticleSearchTagMatchMode.any)
                Text(L10n.articleSearchTagMatchModeAll).tag(ArticleSearchTagMatchMode.all)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if tags.isEmpty {
                Text(L10n.articleSearchTagsEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tags) { tag in
                    Toggle(tag.name, isOn: tagBinding(for: tag))
                        .toggleStyle(.checkbox)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 180)
    }

    private func tagBinding(for tag: TagRecord) -> Binding<Bool> {
        Binding(
            get: {
                guard let uuid = UUID(uuidString: tag.id) else {
                    return false
                }
                return searchState.tagIDs.contains(uuid)
            },
            set: { isOn in
                guard let uuid = UUID(uuidString: tag.id) else {
                    return
                }
                if isOn {
                    searchState.tagIDs.insert(uuid)
                } else {
                    searchState.tagIDs.remove(uuid)
                }
            }
        )
    }

    private var searchDatePicker: some View {
        Picker("", selection: $searchState.dateFilter) {
            ForEach(ArticleSearchDateFilter.allCases) { dateFilter in
                Text(label(for: dateFilter)).tag(dateFilter)
            }
        }
        .labelsHidden()
        .frame(width: 118)
    }

    private var searchStatusPicker: some View {
        Picker("", selection: $searchState.statusFilter) {
            ForEach(ArticleSearchStatusFilter.allCases) { statusFilter in
                Text(label(for: statusFilter)).tag(statusFilter)
            }
        }
        .labelsHidden()
        .frame(width: 122)
    }

    @ViewBuilder
    private var resultList: some View {
        if usesNativeArticleList {
            NativeArticleSearchResultTableView(
                snapshots: snapshots,
                selectedID: $selectedResultID,
                onOpenOriginal: openOriginal,
                onOpenInReader: openInReaderWindow
            )
            .frame(minWidth: 260, idealWidth: 340)
            .task(id: snapshots.map(\.id)) {
                if selectedResultID == nil || !snapshots.contains(where: { $0.id == selectedResultID }) {
                    selectedResultID = snapshots.first?.id
                }
            }
        } else {
            List(snapshots) { snapshot in
                ArticleSearchResultRow(snapshot: snapshot) {
                    openOriginal(snapshot)
                }
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            openInReaderWindow(snapshot)
                        }
                        .exclusively(before: TapGesture(count: 1).onEnded {
                            selectedResultID = snapshot.id
                            isResultListFocused = true
                        })
                )
                .listRowBackground(
                    snapshot.id == selectedResultID
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .accessibilityAddTraits(snapshot.id == selectedResultID ? [.isSelected] : [])
            }
            .listStyle(.inset)
            .frame(minWidth: 260, idealWidth: 340)
            .focusable()
            .focused($isResultListFocused)
            .onKeyPress(.downArrow) {
                selectAdjacentResult(offset: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                selectAdjacentResult(offset: -1)
                return .handled
            }
            .onKeyPress(.return) {
                if let selectedSnapshot {
                    openInReaderWindow(selectedSnapshot)
                }
                return .handled
            }
            .task(id: snapshots.map(\.id)) {
                // Nach jeder neuen Suche/Filteraenderung eine sinnvolle Tastatur-Ausgangsposition
                // setzen: bestehende Auswahl behalten, falls sie noch in den Treffern vorkommt,
                // sonst den ersten Treffer vorauswaehlen.
                if selectedResultID == nil || !snapshots.contains(where: { $0.id == selectedResultID }) {
                    selectedResultID = snapshots.first?.id
                }
            }
        }
    }

    private func selectAdjacentResult(offset: Int) {
        guard !snapshots.isEmpty else {
            return
        }

        guard let currentID = selectedResultID,
              let currentIndex = snapshots.firstIndex(where: { $0.id == currentID }) else {
            selectedResultID = snapshots.first?.id
            return
        }

        let newIndex = max(0, min(snapshots.count - 1, currentIndex + offset))
        selectedResultID = snapshots[newIndex].id
    }

    @ViewBuilder
    private var previewPanel: some View {
        if let selectedSnapshot {
            ArticleSearchPreviewView(
                snapshot: selectedSnapshot,
                theme: RuleDialogTheme(colorScheme: colorScheme),
                onOpenInReader: { openInReaderWindow(selectedSnapshot) },
                onOpenOriginal: { openOriginal(selectedSnapshot) }
            )
        } else {
            ContentUnavailableView(
                L10n.articleSearchPreviewEmptyTitle,
                systemImage: "doc.text.magnifyingglass",
                description: Text(L10n.articleSearchPreviewEmptyDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedSnapshot: ArticleListSnapshot? {
        snapshots.first { $0.id == selectedResultID }
    }

    private func openInReaderWindow(_ snapshot: ArticleListSnapshot) {
        guard let uuid = UUID(uuidString: snapshot.id) else {
            return
        }

        openWindow(value: ArticleWindowRequest(articleID: uuid))
    }

    private var emptyState: some View {
        Group {
            if let loadErrorMessage {
                ContentUnavailableView(
                    L10n.articleSearchNoResultsTitle,
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(loadErrorMessage)
                )
            } else if committedState.query.normalizedText.isEmpty {
                ContentUnavailableView(
                    L10n.articleSearchNoResultsTitle,
                    systemImage: "magnifyingglass",
                    description: Text(L10n.articleListEmptyDescription)
                )
            } else {
                ContentUnavailableView(
                    L10n.articleSearchNoResultsTitle,
                    systemImage: "magnifyingglass",
                    description: Text(L10n.articleSearchNoResultsDescription(committedState.query.normalizedText))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clearSearch() {
        searchState = ArticleSearchWindowState()
        // P4: debounced Text sofort zurücksetzen, damit Treffer/Leer-Zustand ohne
        // 250 ms Lag folgen.
        debouncedSearchText = ""
    }

    private var searchLoadToken: String {
        [
            debouncedSearchText,
            searchState.field.rawValue,
            searchState.feedID?.uuidString ?? "all-feeds",
            searchState.tagIDs.map(\.uuidString).sorted().joined(separator: ","),
            searchState.tagMatchMode.rawValue,
            searchState.dateFilter.rawValue,
            searchState.statusFilter.rawValue
        ].joined(separator: "#")
    }

    private func loadFeeds() {
        guard let database else {
            feeds = []
            tags = []
            return
        }
        feeds = (try? FeedStore(database: database).feeds()) ?? []
    }

    private func loadTags() {
        guard let database else {
            tags = []
            return
        }

        tags = TagStore.tagsIgnoringErrors(database: database)
    }

    private func loadSnapshots() {
        guard let database else {
            snapshots = []
            loadErrorMessage = "Die lokale Artikeldatenbank konnte nicht geöffnet werden."
            return
        }

        do {
            snapshots = try ArticleStore(database: database).searchArticles(
                state: committedState,
                limit: ArticleFetchLimits.searchResults
            )
            loadErrorMessage = nil
        } catch {
            snapshots = []
            loadErrorMessage = error.localizedDescription
        }
    }

    private func openOriginal(_ snapshot: ArticleListSnapshot) {
        guard let link = snapshot.link, let url = URL(string: link) else {
            return
        }

        ArticleOriginalBrowserLauncher.open(url)
    }

    private func label(for field: ArticleSearchField) -> String {
        switch field {
        case .all:
            return L10n.articleSearchFieldAll
        case .title:
            return L10n.articleSearchFieldTitle
        case .summary:
            return L10n.articleSearchFieldSummary
        case .content:
            return L10n.articleSearchFieldContent
        }
    }

    private func label(for dateFilter: ArticleSearchDateFilter) -> String {
        switch dateFilter {
        case .anytime:
            return L10n.articleSearchDateAnytime
        case .today:
            return L10n.articleSearchDateToday
        case .thisWeek:
            return L10n.articleSearchDateThisWeek
        }
    }

    private func label(for statusFilter: ArticleSearchStatusFilter) -> String {
        switch statusFilter {
        case .all:
            return L10n.articleSearchStatusAll
        case .unread:
            return L10n.articleSearchStatusUnread
        case .read:
            return L10n.articleSearchStatusRead
        case .starred:
            return L10n.articleSearchStatusStarred
        case .archived:
            return L10n.articleSearchStatusArchived
        }
    }
}

private struct ArticleSearchResultRow: View {
    let snapshot: ArticleListSnapshot
    let onOpenOriginal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(snapshot.feedTitle)
                    Text("·")
                    Text(formattedArticleDate(snapshot.publishedAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let summary = snapshot.summary.map(ReaderContentRenderer.htmlToPlainText), !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            Button {
                onOpenOriginal()
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help(L10n.articleOpenOriginalCommand)
        }
        .padding(.vertical, 6)
    }
}

private struct ArticleSearchPreviewView: View {
    let snapshot: ArticleListSnapshot
    let theme: RuleDialogTheme
    let onOpenInReader: () -> Void
    let onOpenOriginal: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(snapshot.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                HStack(spacing: 6) {
                    Text(snapshot.feedTitle)
                    Text("·")
                    Text(formattedArticleDate(snapshot.publishedAt))
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if let summary = snapshot.summary.map(ReaderContentRenderer.htmlToPlainText), !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        onOpenInReader()
                    } label: {
                        Text(L10n.articleSearchOpenInReader)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onOpenOriginal()
                    } label: {
                        Label(L10n.articleOpenOriginalCommand, systemImage: "safari")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(theme.card2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(snapshot.link == nil)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Geteilter Datums-Formatierer für die Suchergebnis-Zeile — sowohl die
/// SwiftUI-Baseline (`ArticleSearchResultRow` in dieser Datei) als auch die
/// native AppKit-Zelle (`NativeArticleSearchResultCellView`) nutzen ihn, damit
/// dasselbe Suchergebnis unabhängig von der aktiven Listen-Implementierung
/// identisch formatiert wird (vorher hatte die native Zelle einen eigenen,
/// abweichenden `DateFormatter`).
func formattedArticleDate(_ date: Date?) -> String {
    guard let date else {
        return "Unbekannt"
    }

    return date.formatted(date: .abbreviated, time: .omitted)
}
