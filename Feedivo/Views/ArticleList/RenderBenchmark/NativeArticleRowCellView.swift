import AppKit

#if DEBUG
/// NetNewsWire-artige, rein native Artikel-Zeile für den Render-Benchmark —
/// bewusst OHNE `NSHostingView`/SwiftUI, um echte `NSTableView`-
/// Zellwiederverwendung zu ermöglichen (siehe Design-Doc, Abschnitt 3).
final class NativeArticleRowCellView: NSTableCellView {
    private let unreadIndicator = NSView()
    private let previewImageView = NSImageView()
    private let faviconImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let metadataField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")
    private let starButton = NSButton(image: NSImage(), target: nil, action: nil)

    private lazy var metadataRow = NSStackView(views: [faviconImageView, metadataField])
    private lazy var textStack = NSStackView(views: [titleField, metadataRow, summaryField])
    private lazy var rootStack = NSStackView(views: [unreadIndicator, previewImageView, textStack, starButton])

    // Whole-Branch-Review-Fund: diese vier Constraints trugen bisher feste,
    // unskalierte Literale (56/11/24pt) — gespeichert als Properties, damit
    // `configure(...)` ihre `.constant` je `interfaceTextSize` aktualisieren
    // kann, analog zu `ArticleRowView.previewImageSide`/`.scaled(11)`/
    // `.scaled(24)` auf der SwiftUI-Baseline-Seite.
    private var previewImageWidthConstraint: NSLayoutConstraint!
    private var previewImageHeightConstraint: NSLayoutConstraint!
    private var faviconWidthConstraint: NSLayoutConstraint!
    private var faviconHeightConstraint: NSLayoutConstraint!
    private var starButtonWidthConstraint: NSLayoutConstraint!
    private var starButtonHeightConstraint: NSLayoutConstraint!

    /// Erhöht sich bei jedem `configure(...)`-Aufruf — dient
    /// `NativeArticleImageLoadGuard` als "aktueller Stand dieser Zelle".
    private var currentLoadToken = 0
    private var starButtonAction: (() -> Void)?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

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
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        metadataRow.orientation = .horizontal
        metadataRow.alignment = .centerY
        metadataRow.spacing = 4

        unreadIndicator.wantsLayer = true
        unreadIndicator.layer?.cornerRadius = 4
        NSLayoutConstraint.activate([
            unreadIndicator.widthAnchor.constraint(equalToConstant: 8),
            unreadIndicator.heightAnchor.constraint(equalToConstant: 8)
        ])

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageWidthConstraint = previewImageView.widthAnchor.constraint(equalToConstant: 56)
        previewImageHeightConstraint = previewImageView.heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([previewImageWidthConstraint, previewImageHeightConstraint])

        faviconImageView.imageScaling = .scaleProportionallyUpOrDown
        faviconWidthConstraint = faviconImageView.widthAnchor.constraint(equalToConstant: 11)
        faviconHeightConstraint = faviconImageView.heightAnchor.constraint(equalToConstant: 11)
        NSLayoutConstraint.activate([faviconWidthConstraint, faviconHeightConstraint])

        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail

        metadataField.font = .systemFont(ofSize: 11)
        metadataField.textColor = .secondaryLabelColor

        summaryField.font = .systemFont(ofSize: 13)
        summaryField.textColor = .secondaryLabelColor
        summaryField.lineBreakMode = .byTruncatingTail

        starButton.imagePosition = .imageOnly
        starButton.isBordered = false
        starButton.target = self
        starButton.action = #selector(starButtonTapped)
        starButtonWidthConstraint = starButton.widthAnchor.constraint(equalToConstant: 24)
        starButtonHeightConstraint = starButton.heightAnchor.constraint(equalToConstant: 24)
        NSLayoutConstraint.activate([starButtonWidthConstraint, starButtonHeightConstraint])
    }

    func configure(with snapshot: ArticleListSnapshot, interfaceTextSize: InterfaceTextSize, onToggleStarred: @escaping () -> Void) {
        currentLoadToken += 1
        let loadToken = currentLoadToken
        starButtonAction = onToggleStarred

        // Whole-Branch-Review-Fund: diese Zelle verwendete bisher überall
        // unskalierte Literale statt `interfaceTextSize.scaled(...)` wie die
        // SwiftUI-Baseline (`ArticleRowView`) — dadurch renderten beide
        // Benchmark-Varianten sichtbar unterschiedlich, sobald die
        // Textgröße-Einstellung nicht auf "Standard" stand.
        previewImageWidthConstraint.constant = interfaceTextSize.scaled(56)
        previewImageHeightConstraint.constant = interfaceTextSize.scaled(56)
        faviconWidthConstraint.constant = interfaceTextSize.scaled(11)
        faviconHeightConstraint.constant = interfaceTextSize.scaled(11)
        starButtonWidthConstraint.constant = interfaceTextSize.scaled(24)
        starButtonHeightConstraint.constant = interfaceTextSize.scaled(24)

        unreadIndicator.layer?.backgroundColor = snapshot.isRead
            ? NSColor.clear.cgColor
            : NSColor.controlAccentColor.cgColor

        titleField.stringValue = snapshot.title
        titleField.font = .systemFont(ofSize: interfaceTextSize.scaled(14), weight: snapshot.isRead ? .regular : .semibold)
        titleField.textColor = snapshot.isRead ? .secondaryLabelColor : .labelColor

        metadataField.font = .systemFont(ofSize: interfaceTextSize.scaled(11))
        metadataField.stringValue = [
            snapshot.feedTitle,
            snapshot.publishedAt.map(Self.dateFormatter.string)
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        summaryField.font = .systemFont(ofSize: interfaceTextSize.scaled(13))
        summaryField.stringValue = snapshot.summary ?? ""
        summaryField.isHidden = snapshot.summary == nil

        starButton.image = NSImage(
            systemSymbolName: snapshot.isStarred ? "star.fill" : "star",
            accessibilityDescription: nil
        )

        previewImageView.image = nil
        faviconImageView.image = nil

        if let imageURLString = snapshot.imageURL, let imageURL = URL(string: imageURLString) {
            Task { [weak self] in
                let image = await ImageCacheService.shared.image(
                    for: imageURL,
                    targetPixelSize: CGSize(width: 112, height: 112)
                )
                guard let self,
                      NativeArticleImageLoadGuard.shouldApplyLoadedImage(
                          requestedToken: loadToken,
                          currentToken: self.currentLoadToken
                      )
                else { return }
                self.previewImageView.image = image
            }
        }

        if let faviconURLString = snapshot.faviconURL, let faviconURL = URL(string: faviconURLString) {
            Task { [weak self] in
                let image = await ImageCacheService.shared.image(for: faviconURL)
                guard let self,
                      NativeArticleImageLoadGuard.shouldApplyLoadedImage(
                          requestedToken: loadToken,
                          currentToken: self.currentLoadToken
                      )
                else { return }
                self.faviconImageView.image = image
            }
        }
    }

    @objc private func starButtonTapped() {
        starButtonAction?()
    }
}
#endif
