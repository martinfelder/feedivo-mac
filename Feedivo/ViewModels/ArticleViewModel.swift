import Observation

@Observable
final class ArticleViewModel {
    func toggleRead(_ article: Article) {
        article.isRead.toggle()
    }

    func toggleStarred(_ article: Article) {
        article.isStarred.toggle()
    }

    func markReadIfNeeded(_ article: Article?, isEnabled: Bool) {
        guard isEnabled, let article, !article.isRead else {
            return
        }

        article.isRead = true
    }
}
