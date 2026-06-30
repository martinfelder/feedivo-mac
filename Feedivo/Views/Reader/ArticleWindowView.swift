import SwiftData
import SwiftUI

struct ArticleWindowRequest: Codable, Hashable, Identifiable {
    let articleID: UUID

    var id: UUID {
        articleID
    }
}

struct ArticleWindowView: View {
    let request: ArticleWindowRequest

    @Query private var articles: [Article]
    @State private var selectedArticleID: UUID
    @State private var isMetadataInspectorPresented = false
    @State private var articleForRuleCreation: Article?
    @State private var articleExportRequest: ArticleExportRequest?

    init(request: ArticleWindowRequest) {
        self.request = request
        self._selectedArticleID = State(initialValue: request.articleID)
        self._articles = Query(sort: ArticleListQuery.sortDescriptors)
    }

    private var selectedArticle: Article? {
        articles.first { article in
            article.id == selectedArticleID
        }
    }

    private var selectedArticleIndex: Int? {
        articles.firstIndex { article in
            article.id == selectedArticleID
        }
    }

    private var previousArticle: Article? {
        guard let selectedArticleIndex, selectedArticleIndex > articles.startIndex else {
            return nil
        }

        return articles[articles.index(before: selectedArticleIndex)]
    }

    private var nextArticle: Article? {
        guard let selectedArticleIndex else {
            return nil
        }

        let nextIndex = articles.index(after: selectedArticleIndex)
        guard nextIndex < articles.endIndex else {
            return nil
        }

        return articles[nextIndex]
    }

    var body: some View {
        Group {
            if let selectedArticle {
                ReaderView(
                    article: selectedArticle,
                    isMetadataInspectorPresented: $isMetadataInspectorPresented,
                    canSelectPreviousArticle: previousArticle != nil,
                    canSelectNextArticle: nextArticle != nil,
                    selectPreviousArticle: selectPreviousArticle,
                    selectNextArticle: selectNextArticle,
                    onRequestCreateRuleFromArticle: requestCreateRuleFromArticle,
                    onRequestExportArticle: requestExportArticle
                )
                .id(selectedArticle.id)
            } else {
                ContentUnavailableView(
                    L10n.articleWindowMissingTitle,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(L10n.articleWindowMissingDescription)
                )
            }
        }
        .navigationTitle(selectedArticle?.title ?? String(localized: "article.window.missing.title"))
        .onAppear {
            ArticleWindowSettings.rememberOpenArticleID(selectedArticleID)
        }
        .onChange(of: selectedArticleID) { oldValue, newValue in
            ArticleWindowSettings.forgetOpenArticleID(oldValue)
            ArticleWindowSettings.rememberOpenArticleID(newValue)
        }
        .onDisappear {
            ArticleWindowSettings.forgetOpenArticleID(selectedArticleID)
        }
        .sheet(item: $articleForRuleCreation) { article in
            RuleWizardView(sourceArticle: article)
        }
        .sheet(item: $articleExportRequest) { request in
            ArticleExportSheet(request: request) {
                articleExportRequest = nil
            }
        }
    }

    private func selectPreviousArticle() {
        guard let previousArticle else {
            return
        }

        selectedArticleID = previousArticle.id
    }

    private func selectNextArticle() {
        guard let nextArticle else {
            return
        }

        selectedArticleID = nextArticle.id
    }

    private func requestCreateRuleFromArticle(_ article: Article) {
        articleForRuleCreation = article
    }

    private func requestExportArticle(_ article: Article) {
        let request = ArticleExportRequest(snapshot: ArticleExportSnapshot(article: article))

        DispatchQueue.main.async {
            articleExportRequest = request
        }
    }
}
