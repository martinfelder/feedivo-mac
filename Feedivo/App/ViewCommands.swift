import SwiftUI

struct ViewCommands: Commands {
    @AppStorage(ArticleSortOption.storageKey)
    private var articleSortRawValue = ArticleSortOption.newestFirst.rawValue

    var body: some Commands {
        CommandMenu(L10n.viewCommandsMenu) {
            Menu(L10n.articleSortMenuTitle) {
                ForEach(ArticleSortOption.allCases) { sortOption in
                    Button {
                        articleSortRawValue = sortOption.rawValue
                    } label: {
                        if sortOption == articleSortOption {
                            Label(sortOption.label, systemImage: "checkmark")
                        } else {
                            Text(sortOption.label)
                        }
                    }
                }
            }
        }
    }

    private var articleSortOption: ArticleSortOption {
        ArticleSortOption.resolved(from: articleSortRawValue)
    }
}
