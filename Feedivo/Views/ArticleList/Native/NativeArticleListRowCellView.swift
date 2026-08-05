import AppKit

/// Reine AppKit-Zelle für die native Hauptartikelliste (Produktiv-Pendant zum
/// `#if DEBUG`-Render-Benchmark-Spike unter `RenderBenchmark/`, bewusst als
/// eigenständige Klasse — kein Umbau des Spike-Codes). Volle Parität mit
/// `ArticleRowView` (SwiftUI-Baseline): Bildposition, Feedname-Position,
/// variable Zusammenfassungszeilen, Datumsanzeige-Modus, Barrierefreiheit.
final class NativeArticleListRowCellView: NSTableCellView {
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
        rootStack.spacing = 12
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
        textStack.spacing = 6
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)

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

    func configure(
        with snapshot: ArticleListSnapshot,
        interfaceTextSize: InterfaceTextSize,
        imagePosition: ArticleListImagePosition,
        feedNamePosition: ArticleListFeedNamePosition,
        showsFeedName: Bool,
        summaryLineCount: Int,
        dateDisplayMode: ArticleDateDisplayMode,
        onToggleStarred: @escaping () -> Void
    ) {
        currentLoadToken += 1
        let loadToken = currentLoadToken
        starButtonAction = onToggleStarred

        previewImageWidthConstraint.constant = interfaceTextSize.scaled(56 as CGFloat)
        previewImageHeightConstraint.constant = interfaceTextSize.scaled(56 as CGFloat)
        faviconWidthConstraint.constant = interfaceTextSize.scaled(11 as CGFloat)
        faviconHeightConstraint.constant = interfaceTextSize.scaled(11 as CGFloat)
        starButtonWidthConstraint.constant = interfaceTextSize.scaled(24 as CGFloat)
        starButtonHeightConstraint.constant = interfaceTextSize.scaled(24 as CGFloat)

        unreadIndicator.layer?.backgroundColor = snapshot.isRead
            ? NSColor.clear.cgColor
            : NSColor.controlAccentColor.cgColor

        titleField.stringValue = snapshot.title
        titleField.font = .systemFont(ofSize: interfaceTextSize.scaled(14 as CGFloat), weight: snapshot.isRead ? .regular : .semibold)
        titleField.textColor = snapshot.isRead ? .secondaryLabelColor : .labelColor

        let showsFeedNameAndFavicon = showsFeedName && (snapshot.feedTitle.isEmpty == false)
        metadataField.font = .systemFont(ofSize: interfaceTextSize.scaled(11 as CGFloat))
        metadataField.stringValue = Self.metadataText(
            feedTitle: snapshot.feedTitle,
            publishedAt: snapshot.publishedAt,
            showsFeedNameAndFavicon: showsFeedNameAndFavicon,
            dateDisplayMode: dateDisplayMode
        )
        metadataRow.isHidden = metadataField.stringValue.isEmpty
        faviconImageView.isHidden = !showsFeedNameAndFavicon

        summaryField.font = .systemFont(ofSize: interfaceTextSize.scaled(13 as CGFloat))
        summaryField.maximumNumberOfLines = summaryLineCount
        if let summary = snapshot.summary, !summary.isEmpty, summaryLineCount > 0 {
            summaryField.stringValue = summary
            summaryField.isHidden = false
        } else {
            summaryField.stringValue = ""
            summaryField.isHidden = true
        }

        // Reihenfolge Titel/Metadaten-Zeile im Textstapel spiegeln
        // ArticleListFeedNamePosition (vor/nach dem Titel) — identisch zu
        // `ArticleRowView`s `feedNamePosition == .beforeTitle`-Verzweigung.
        textStack.removeArrangedSubview(titleField)
        textStack.removeArrangedSubview(metadataRow)
        textStack.removeArrangedSubview(summaryField)
        if feedNamePosition == .beforeTitle {
            textStack.addArrangedSubview(metadataRow)
            textStack.addArrangedSubview(titleField)
        } else {
            textStack.addArrangedSubview(titleField)
            textStack.addArrangedSubview(metadataRow)
        }
        textStack.addArrangedSubview(summaryField)

        // Bildposition links/rechts/aus spiegeln ArticleListImagePosition —
        // identisch zu `ArticleRowView`s `imagePosition == .left`-Verzweigung.
        rootStack.removeArrangedSubview(unreadIndicator)
        rootStack.removeArrangedSubview(previewImageView)
        rootStack.removeArrangedSubview(textStack)
        rootStack.removeArrangedSubview(starButton)
        previewImageView.isHidden = imagePosition == .hidden
        switch imagePosition {
        case .left:
            rootStack.addArrangedSubview(previewImageView)
            rootStack.addArrangedSubview(textStack)
        case .right, .hidden:
            rootStack.addArrangedSubview(textStack)
            if imagePosition == .right {
                rootStack.addArrangedSubview(previewImageView)
            }
        }
        rootStack.addArrangedSubview(starButton)
        rootStack.insertArrangedSubview(unreadIndicator, at: 0)

        starButton.image = NSImage(
            systemSymbolName: snapshot.isStarred ? "star.fill" : "star",
            accessibilityDescription: snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd
        )

        previewImageView.image = nil
        faviconImageView.image = nil

        if imagePosition != .hidden, let imageURLString = snapshot.imageURL, let imageURL = URL(string: imageURLString) {
            let side = interfaceTextSize.scaled(56 as CGFloat)
            Task { [weak self] in
                let image = await ImageCacheService.shared.image(
                    for: imageURL,
                    targetPixelSize: CGSize(width: side * 2, height: side * 2)
                )
                guard let self,
                      NativeArticleListImageLoadGuard.shouldApplyLoadedImage(
                          requestedToken: loadToken,
                          currentToken: self.currentLoadToken
                      )
                else { return }
                self.previewImageView.image = image
            }
        }

        if showsFeedNameAndFavicon, let faviconURLString = snapshot.faviconURL, let faviconURL = URL(string: faviconURLString) {
            Task { [weak self] in
                let image = await ImageCacheService.shared.image(for: faviconURL)
                guard let self,
                      NativeArticleListImageLoadGuard.shouldApplyLoadedImage(
                          requestedToken: loadToken,
                          currentToken: self.currentLoadToken
                      )
                else { return }
                self.faviconImageView.image = image
            }
        }

        setAccessibilityLabel(Self.accessibilityLabel(for: snapshot))
    }

    static func metadataText(
        feedTitle: String?,
        publishedAt: Date?,
        showsFeedNameAndFavicon: Bool,
        dateDisplayMode: ArticleDateDisplayMode
    ) -> String {
        let feedNamePart = showsFeedNameAndFavicon ? feedTitle : nil
        return [feedNamePart, publishedAt?.feedivoDisplay(mode: dateDisplayMode)]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    static func accessibilityLabel(for snapshot: ArticleListSnapshot) -> String {
        var parts = [snapshot.title]
        if !snapshot.isRead {
            parts.append(L10n.articleRowUnreadText)
        }
        if snapshot.isStarred {
            parts.append(L10n.articleRowStarredText)
        }
        return parts.joined(separator: ", ")
    }

    @objc private func starButtonTapped() {
        starButtonAction?()
    }
}
