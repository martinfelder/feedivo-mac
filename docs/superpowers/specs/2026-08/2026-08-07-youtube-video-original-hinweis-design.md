# Design: Hinweis auf YouTube-Video im nativen Reader

**Datum:** 2026-08-07
**Status:** Zur Review

## Kontext

Direkter Anschluss an den YouTube-Abo-Fix vom selben Tag (Consent-Cookie-Bypass in
`FeedDiscoveryService`, siehe Commit-Historie): YouTube-Kanäle lassen sich jetzt über den
"Feed hinzufügen"-Dialog abonnieren, da YouTube-Kanalseiten einen nativen RSS/Atom-Feed
(`youtube.com/feeds/videos.xml?channel_id=...`) über ein `<link rel="alternate">`-Tag
verlinken.

Ein Video-Artikel aus einem solchen Feed lässt sich in der bestehenden "Original-Ansicht"
(WKWebView, lädt `snapshot.link`) bereits abspielen — die echte YouTube-Watch-Seite lädt
korrekt, inklusive Kommentaren. Einzige Einschränkung: kein eingeloggter Zustand (Feedivos
WKWebView nutzt eine eigene, von Safari/Chrome getrennte Cookie-Sitzung) — für reines
Ansehen unproblematisch, für personalisierte Funktionen (Login, eigene Playlists) müsste
sich der Nutzer dort separat anmelden.

Der native Reader (SwiftUI-Renderer) zeigt für einen YouTube-Video-Artikel nur den aus dem
Feed vorhandenen Text (Titel, Beschreibung, Vorschaubild) — kein Hinweis darauf, dass sich
das eigentliche Video in der Original-Ansicht ansehen lässt. Nutzer, die nicht wissen, dass
dieser Umschalter existiert, finden das Video sonst nicht.

## Ziel

Im nativen Reader einen Hinweis-Banner einblenden, sobald der aktuell angezeigte Artikel ein
YouTube-Video ist — mit einem direkten Weg, in die Original-Ansicht zu wechseln.

## Nicht-Ziele

- Kein eingebetteter Video-Player im nativen Reader (vom Nutzer explizit nicht gewünscht —
  die bestehende Original-Ansicht reicht aus, u. a. weil dort auch Kommentare sichtbar sind
  und ein Login möglich ist).
- Keine YouTube-spezifische Anmeldung/Session-Verwaltung innerhalb von Feedivo.
- Keine Erkennung über die Feed-Quelle oder das `yt:videoId`-Feld — reine Link-Erkennung
  reicht (siehe „Betrachtete Ansätze").

## Betrachtete Ansätze

1. **Erkennung über den Artikel-Link (gewählt):** Ein reiner, isoliert testbarer Helfer prüft
   `originalURL` (dieselbe URL, die "Original-Ansicht" und "Im Browser öffnen" bereits
   verwenden) gegen bekannte YouTube-Video-URL-Muster (`youtube.com/watch`,
   `youtube.com/shorts/…`, `youtu.be/…`). Keine neue Datenquelle, kein zusätzlicher
   Netzwerk-Call.
2. **Erkennung über die Feed-Quelle** (verworfen): Nur Artikel aus einem
   `youtube.com/feeds/videos.xml`-Feed markieren. Genauer im Sinne von "nur bei echten
   YouTube-Abos", aber deutlich invasiver — die Feed-URL müsste bis in den
   `ArticleReaderSnapshot` durchgereicht werden, was aktuell nicht vorhanden ist. Zusätzlich
   würde das einen Artikel, der zufällig aus einem anderen Feed auf ein YouTube-Video
   verlinkt, fälschlich ausschließen — inhaltlich wäre der Hinweis dort genauso richtig.
3. **Erkennung über `yt:videoId` im rohen Feed-XML** (verworfen): Würde eine
   YouTube-spezifische Erweiterung des FeedKit-basierten Parsings brauchen. Für einen reinen
   Hinweis-Banner unverhältnismäßig aufwändig.

## Design

### Erkennung

Neuer, eigenständiger Helfer `YouTubeVideoLink` (`Feedivo/Extensions/YouTubeVideoLink.swift`):

```swift
enum YouTubeVideoLink {
    static func isVideoURL(_ url: URL?) -> Bool
}
```

Erkennt Hosts `youtube.com`, `www.youtube.com`, `m.youtube.com` mit Pfad `/watch` oder
`/shorts/…`, sowie den Host `youtu.be` (dort ist praktisch jeder Pfad ein Video-Link). Reine,
synchrone Funktion ohne Seiteneffekte — direkt unit-testbar (Watch-URL, Shorts-URL,
youtu.be-Kurzlink, YouTube-Kanalseite ohne Video als Negativfall, `nil`, fremde Domain).

### Platzierung & UI

Neuer Banner in `SQLiteReaderView.readerHeader(_:)`, direkt unter Titel/Metadaten und vor der
Ordner-/Tag-Chip-Zeile — dadurch nur sichtbar, wenn der native Modus tatsächlich gerendert
wird (`readerHeader` wird ausschließlich im native-Zweig von `ReaderModeContent.body`
aufgerufen, kein zusätzlicher Modus-Check nötig).

Stil orientiert sich am bestehenden `feedErrorBanner`-Muster
(`SQLiteFeedArticleListView.swift:345`) — `HStack` mit Icon, Text, Spacer, Button, farbiger
Hintergrund bei niedriger Opazität — hier in einer "Info"- statt "Warnung"-Färbung (Accent-
statt Orange-Ton, Icon `play.rectangle.fill` statt `exclamationmark.triangle.fill`):

```swift
HStack(spacing: 8) {
    Image(systemName: "play.rectangle.fill")
        .foregroundStyle(.accent)
    Text(L10n.readerYouTubeVideoHintMessage)
        .font(...)
    Spacer()
    Button(L10n.readerYouTubeVideoHintButton) {
        readerDisplayModeRawValue = ReaderDisplayMode.web.rawValue
    }
    .buttonStyle(.borderless)
}
.padding(.horizontal, 12)
.padding(.vertical, 6)
.background(Color.accentColor.opacity(0.12))
```

Der Button setzt direkt den bestehenden `@AppStorage`-Wert `readerDisplayModeRawValue` auf
`.web` — exakt derselbe Mechanismus, den das Toolbar-Picker-Menü bereits verwendet. Kein
neuer State, keine neue Navigation.

### Texte (neue L10n-Keys, DE/EN)

- `readerYouTubeVideoHintMessage`
  - DE: "Dies ist ein YouTube-Video. In der Original-Ansicht kannst du es abspielen und dich
    bei YouTube anmelden."
  - EN: "This is a YouTube video. Switch to the original view to watch it and sign in to
    YouTube."
- `readerYouTubeVideoHintButton`
  - DE: "Original-Ansicht öffnen"
  - EN: "Open Original View"

Werte manuell in `Localizable.xcstrings` ergänzen (Xcodes Auto-Stub-Mechanismus greift bei
indirekten `L10n`-Keys nicht, siehe bestehender CLAUDE.md-Gotcha) — anschließend per
`grep -c` verifizieren.

### Zustandslogik

Kein Dismiss, keine Persistenz. Der Banner erscheint zuverlässig bei jedem erkannten
Video-Artikel im nativen Modus, verschwindet automatisch beim Wechsel in die Original-Ansicht
(da `readerHeader` dort gar nicht mehr gerendert wird) und beim Wechsel zu einem
Nicht-Video-Artikel.

## Testing

- Neue Unit-Tests für `YouTubeVideoLink.isVideoURL(_:)` (Watch-URL, Shorts-URL,
  youtu.be-Kurzlink, YouTube-Kanalseite als Negativfall, beliebige fremde Domain, `nil`).
- Kein neuer Test für die reine UI-Platzierung nötig (kein computer-use für native
  macOS-Apps in dieser Umgebung verfügbar) — manuelle Live-Verifikation durch den Nutzer:
  YouTube-Video-Artikel im nativen Modus öffnen, Banner sichtbar, Klick auf den Button
  wechselt in die Original-Ansicht.

## Umsetzung

Umfang ist klein genug für einen direkten, TDD-basierten Umbau ohne vollen
Subagent-Driven-Development-Zyklus (analog zu vorherigen kleinen Features wie der
Bulk-Benachrichtigungsverwaltung im Organizer): neuer Helfer + Tests, Banner-Ergänzung in
`SQLiteReaderView.swift`, zwei neue L10n-Keys.
