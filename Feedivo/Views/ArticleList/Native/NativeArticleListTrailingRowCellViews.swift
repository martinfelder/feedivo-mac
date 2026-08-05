import AppKit

/// Feste Höhe für beide Trailing-Row-Typen (Pagination-Indikator,
/// "N gelesene Artikel anzeigen"-Button) — unabhängig von
/// `ArticleRowHeightMetrics`, da diese Zeilen keinen Artikelinhalt zeigen.
enum NativeArticleListTrailingRowMetrics {
    static let height: CGFloat = 44
}

/// Zelle für die Pagination-Trailing-Row — ersetzt die SwiftUI-`ProgressView`
/// samt `onAppear`-Ladeauslöser aus der bisherigen `List`-Implementierung.
final class NativeArticleListLoadMoreCellView: NSTableCellView {
    private let indicator = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    private func configureLayout() {
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

/// Zelle für die "N gelesene Artikel anzeigen"-Trailing-Row — ersetzt den
/// SwiftUI-`Button` aus der bisherigen `List`-Implementierung.
final class NativeArticleListShowReadButtonCellView: NSTableCellView {
    private let button = NSButton(title: "", target: nil, action: nil)
    private var buttonAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    private func configureLayout() {
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(buttonTapped)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(count: Int, onTap: @escaping () -> Void) {
        button.title = String.localizedStringWithFormat(L10n.articleListShowReadButtonFormat, count)
        buttonAction = onTap
    }

    @objc private func buttonTapped() {
        buttonAction?()
    }
}
