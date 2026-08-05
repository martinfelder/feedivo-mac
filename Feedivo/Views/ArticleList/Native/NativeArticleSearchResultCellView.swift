import AppKit

/// Reine AppKit-Zelle für die native Suchfenster-Ergebnisliste — schlankeres
/// Pendant zu `NativeArticleListRowCellView`, nach dem Vorbild der SwiftUI-
/// Baseline `ArticleSearchResultRow` (kein Kontextmenü, kein Stern-Button,
/// dafür ein "Original öffnen"-Button).
final class NativeArticleSearchResultCellView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let metadataField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")
    private let openOriginalButton = NSButton(image: NSImage(), target: nil, action: nil)

    private lazy var textStack = NSStackView(views: [titleField, metadataField, summaryField])
    private lazy var rootStack = NSStackView(views: [textStack, openOriginalButton])

    private var openOriginalAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    private func configureLayout() {
        rootStack.orientation = .horizontal
        rootStack.alignment = .top
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)

        titleField.maximumNumberOfLines = 2
        titleField.font = .boldSystemFont(ofSize: 13)

        metadataField.font = .systemFont(ofSize: 11)
        metadataField.textColor = .secondaryLabelColor

        summaryField.maximumNumberOfLines = 2
        summaryField.font = .systemFont(ofSize: 12)
        summaryField.textColor = .secondaryLabelColor

        openOriginalButton.image = NSImage(systemSymbolName: "safari", accessibilityDescription: L10n.articleOpenOriginalCommand)
        openOriginalButton.imagePosition = .imageOnly
        openOriginalButton.isBordered = false
        openOriginalButton.target = self
        openOriginalButton.action = #selector(openOriginalTapped)
        NSLayoutConstraint.activate([
            openOriginalButton.widthAnchor.constraint(equalToConstant: 22),
            openOriginalButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    func configure(with snapshot: ArticleListSnapshot, onOpenOriginal: @escaping () -> Void) {
        openOriginalAction = onOpenOriginal

        titleField.stringValue = snapshot.title
        // Geteilter Formatierer (`formattedArticleDate`, definiert in
        // `ArticleSearchWindowView.swift`) statt eines eigenen `DateFormatter`
        // — sonst zeigt dasselbe Suchergebnis je nach aktiver Listen-
        // Implementierung ein anderes Datumsformat UND ein anderes
        // nil-Datum-Verhalten (SwiftUI-Baseline zeigt "Unbekannt" statt den
        // Datumsteil ganz wegzulassen).
        metadataField.stringValue = "\(snapshot.feedTitle) · \(formattedArticleDate(snapshot.publishedAt))"

        if let summary = Self.summaryText(from: snapshot.summary) {
            summaryField.stringValue = summary
            summaryField.isHidden = false
        } else {
            summaryField.stringValue = ""
            summaryField.isHidden = true
        }
    }

    static func summaryText(from summary: String?) -> String? {
        guard let summary, !summary.isEmpty else {
            return nil
        }
        let plainText = ReaderContentRenderer.htmlToPlainText(summary)
        return plainText.isEmpty ? nil : plainText
    }

    @objc private func openOriginalTapped() {
        openOriginalAction?()
    }
}
