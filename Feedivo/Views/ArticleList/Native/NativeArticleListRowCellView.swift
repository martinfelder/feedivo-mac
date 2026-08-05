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
    // Füllt den Raum zwischen Ungelesen-Punkt (oben) und Stern (unten) in
    // `accessoryStack` — Pendant zu SwiftUIs `Spacer(minLength: 8)` in
    // `ArticleRowView`. Niedrige Content-Hugging-Priorität lässt NSStackView
    // ausschließlich diese View wachsen, Punkt und Stern bleiben an ihrer
    // fixen Größe.
    private let accessorySpacer = NSView()

    private lazy var metadataRow = NSStackView(views: [faviconImageView, metadataField])
    private lazy var textStack = NSStackView(views: [titleField, metadataRow, summaryField])
    // Ungelesen-Punkt oben, Stern unten in einer eigenen rechten Spalte —
    // identisch zu `ArticleRowView`s `VStack { unreadIndicator; Spacer(...); Button(...) }`.
    private lazy var accessoryStack = NSStackView(views: [unreadIndicator, accessorySpacer, starButton])
    private lazy var rootStack = NSStackView(views: [previewImageView, textStack, accessoryStack])

    private var previewImageWidthConstraint: NSLayoutConstraint!
    private var previewImageHeightConstraint: NSLayoutConstraint!
    private var faviconWidthConstraint: NSLayoutConstraint!
    private var faviconHeightConstraint: NSLayoutConstraint!
    private var starButtonWidthConstraint: NSLayoutConstraint!
    private var starButtonHeightConstraint: NSLayoutConstraint!

    /// Erhöht sich bei jedem `configure(...)`-Aufruf — dient
    /// `NativeArticleListImageLoadGuard` als "aktueller Stand dieser Zelle".
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
        // Lässt ausschließlich accessorySpacer wachsen, damit Punkt oben und
        // Stern unten bleiben statt sich in der Mitte zu treffen.
        accessorySpacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.cornerRadius = 6
        previewImageView.layer?.masksToBounds = true
        previewImageWidthConstraint = previewImageView.widthAnchor.constraint(equalToConstant: 56)
        previewImageHeightConstraint = previewImageView.heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([previewImageWidthConstraint, previewImageHeightConstraint])

        faviconImageView.imageScaling = .scaleProportionallyUpOrDown
        faviconWidthConstraint = faviconImageView.widthAnchor.constraint(equalToConstant: 11)
        faviconHeightConstraint = faviconImageView.heightAnchor.constraint(equalToConstant: 11)
        NSLayoutConstraint.activate([faviconWidthConstraint, faviconHeightConstraint])

        titleField.maximumNumberOfLines = 2
        // .byWordWrapping (nicht .byTruncatingTail!) ist nötig, damit der
        // Titel wie in ArticleRowView (`.lineLimit(2)`) über mehrere Zeilen
        // umbricht, statt nach der ersten Zeile abgeschnitten zu werden —
        // .byTruncatingTail kürzt nur EINE Zeile, es bricht nie um.
        titleField.lineBreakMode = .byWordWrapping
        titleField.cell?.wraps = true

        metadataField.font = .systemFont(ofSize: 11)
        metadataField.textColor = .secondaryLabelColor

        summaryField.font = .systemFont(ofSize: 13)
        summaryField.textColor = .secondaryLabelColor
        // Gleicher Umbruch-Fix wie beim Titel — summaryLineCount soll
        // tatsächlich mehrzeilig darstellen, nicht einzeilig abschneiden.
        summaryField.lineBreakMode = .byWordWrapping
        summaryField.cell?.wraps = true

        starButton.imagePosition = .imageOnly
        starButton.isBordered = false
        starButton.target = self
        starButton.action = #selector(starButtonTapped)
        starButtonWidthConstraint = starButton.widthAnchor.constraint(equalToConstant: 24)
        starButtonHeightConstraint = starButton.heightAnchor.constraint(equalToConstant: 24)
        NSLayoutConstraint.activate([starButtonWidthConstraint, starButtonHeightConstraint])

        accessoryStack.orientation = .vertical
        accessoryStack.alignment = .centerX
        accessoryStack.spacing = 0
        NSLayoutConstraint.activate([
            accessoryStack.widthAnchor.constraint(equalToConstant: 28)
        ])
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
        // Tertiär bei gelesenen Artikeln, sonst sekundär — identisch zu
        // ArticleRowView`s `.foregroundStyle(snapshot.isRead ? .tertiary : .secondary)`.
        summaryField.textColor = snapshot.isRead ? .tertiaryLabelColor : .secondaryLabelColor
        summaryField.maximumNumberOfLines = summaryLineCount
        // `snapshot.summary` enthält rohes HTML aus dem Feed — ArticleRowView
        // bekommt den Text nie direkt, sondern über `ArticleListItemSnapshot.init`,
        // das ihn per `ReaderContentRenderer.htmlToPlainText` umwandelt. Diese
        // Zelle liest den SQL-Snapshot direkt, muss dieselbe Umwandlung also
        // selbst anwenden — sonst blieben rohe Tags wie `<p>` sichtbar.
        let plainSummary = snapshot.summary.map(ReaderContentRenderer.htmlToPlainText)
        if let plainSummary, !plainSummary.isEmpty, summaryLineCount > 0 {
            summaryField.stringValue = plainSummary
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
        // accessoryStack (Ungelesen-Punkt + Stern, rechte Spalte) bleibt
        // immer als letztes Element stehen, nur previewImageView wandert.
        rootStack.removeArrangedSubview(previewImageView)
        rootStack.removeArrangedSubview(textStack)
        rootStack.removeArrangedSubview(accessoryStack)
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
        rootStack.addArrangedSubview(accessoryStack)

        starButton.image = NSImage(
            systemSymbolName: snapshot.isStarred ? "star.fill" : "star",
            accessibilityDescription: snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd
        )
        // Gelb wenn gesetzt, sonst sekundär — identisch zu ArticleRowView`s
        // `.foregroundStyle(snapshot.isStarred ? .yellow : .secondary)`.
        starButton.contentTintColor = snapshot.isStarred ? .systemYellow : .secondaryLabelColor

        // Grauer, abgerundeter Platzhalter mit doc.text-Symbol, bis das
        // echte Bild geladen ist bzw. wenn keins vorhanden ist — identisch
        // zu ArticleRowView`s `placeholderImage`.
        previewImageView.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
        previewImageView.imageScaling = .scaleNone
        previewImageView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        previewImageView.contentTintColor = .secondaryLabelColor
        // Fallback-Symbol bis das echte Favicon geladen ist bzw. wenn keins
        // vorhanden ist — identisch zu ArticleRowView`s `metadataFaviconFallback`.
        faviconImageView.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: nil)
        faviconImageView.contentTintColor = .secondaryLabelColor

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
                self.previewImageView.imageScaling = .scaleProportionallyUpOrDown
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
