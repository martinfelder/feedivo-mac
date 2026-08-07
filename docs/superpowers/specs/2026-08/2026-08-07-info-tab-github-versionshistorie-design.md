# Design: Info-Tab — GitHub-Link + Versionshistorie

**Datum:** 2026-08-07
**Status:** Zur Review

## Kontext

Der Settings-Tab "Info" (`AboutSettingsView.swift`) zeigt aktuell nur App-Icon, Name,
Version/Build-Nummer sowie den Update-Check-Bereich (automatischer Schalter + manueller
Prüf-Button bzw. Homebrew-Hinweis). Es gibt keine Möglichkeit, direkt aus der App heraus
zum GitHub-Repository zu springen oder frühere Versionsänderungen nachzulesen — dafür
müsste man aktuell manuell in `CHANGELOG.md` im Repo nachsehen.

`CHANGELOG.md` liegt am Repo-Root und wird bei jedem Versions-Bump (`scripts/
bump_version.sh`) um einen neuen Eintrag ergänzt (Format: `## [Version] - Datum`-
Überschrift, gefolgt von `- `-Aufzählungspunkten in einfacher Sprache). Sie ist bisher
NICHT im App-Bundle enthalten — kein Zugriff zur Laufzeit möglich.

Für Listen-artige Verlaufsdaten existiert im Projekt bereits ein etabliertes Muster:
eigenständiges Fenster als `Window(id:)`-Scene in `FeedivoApp.swift`, geöffnet über einen
Button in den Einstellungen (Vorbild: `CleanupHistoryWindowView.swift` für den
Bereinigungsverlauf).

## Ziel

1. Ein Link im Info-Tab, der das (private) GitHub-Repository im Standardbrowser öffnet.
2. Ein Button im Info-Tab, der ein neues Fenster mit den letzten 15 Versionseinträgen aus
   `CHANGELOG.md` öffnet (neueste zuerst), inkl. Link zur vollständigen Historie auf
   GitHub für ältere Einträge.

## Betrachtete Ansätze (Versionshistorie)

1. **In-App-Fenster mit gebündelter CHANGELOG.md (gewählt).** Funktioniert offline,
   zeigt immer exakt den Stand des installierten Builds, folgt dem bereits etablierten
   Fenster-Muster (siehe `CleanupHistoryWindowView`). Erfordert einen einmaligen
   Bündelungs-Mechanismus (siehe unten).
2. **Reiner Link zu GitHub (verworfen).** Kein zusätzlicher Anzeige-Code nötig, aber
   braucht Internet und funktioniert nur eingeloggt (Repo ist privat) — für eine
   Kernfunktion wie "was hat sich geändert" unnötig fragil, wenn die Daten ohnehin lokal
   im Repo vorliegen.

Nutzerentscheidung: Ansatz 1, mit Ansatz 2 als Ergänzung für ältere, nicht mehr lokal
angezeigte Einträge.

## Architektur

### A) Info-Tab-Erweiterung (`AboutSettingsView.swift`)

Zwei neue Zeilen unterhalb des bestehenden Update-Check-Bereichs, innerhalb derselben
`GeneralSettingsSection`:

- `Link(destination:)` "GitHub-Repository öffnen" → `https://github.com/martinfelder/
  feedivo-mac`. Öffnet im Standardbrowser über SwiftUIs `Link`, kein `NSWorkspace`-Aufruf
  nötig (dasselbe Verhalten wie der bestehende `Link` in `FeedPropertiesView.swift`).
- `Button` "Versionshistorie anzeigen" → `openWindow(id: VersionHistoryWindowView.
  windowID)` (via `@Environment(\.openWindow)`, analog zum bestehenden
  Bereinigungsverlauf-Button in `CleanupSettingsView`).

Neue L10n-Keys: `settingsAboutGitHubLink`, `settingsAboutVersionHistoryButton`.

### B) Datenquelle: `CHANGELOG.md` im Bundle

`CHANGELOG.md` bleibt alleinige Quelle der Wahrheit am Repo-Root (weiterhin auch von
`scripts/create_github_release.sh` für Appcast-Release-Notes genutzt). Für den
Bundle-Zugriff wird eine Kopie unter `Feedivo/Resources/CHANGELOG.md` gepflegt:

- `Feedivo/Resources/` ist Teil des file-system-synchronisierten Xcode-Ordners
  (dieselbe Gruppe, die bereits `Assets.xcassets`, `Fonts/` etc. automatisch als
  Bundle-Resources aufnimmt) — die Kopie wird dadurch ohne manuelle
  `project.pbxproj`-Bearbeitung automatisch mitgebaut.
- `scripts/bump_version.sh` kopiert `CHANGELOG.md` nach `Feedivo/Resources/
  CHANGELOG.md`, direkt nachdem es die Root-Datei um den neuen Eintrag ergänzt hat (in
  derselben Stelle, an der `CHANGELOG` bereits zu `git add` hinzugefügt wird) — die
  Bundle-Kopie ist dadurch ab dem nächsten Versions-Bump automatisch aktuell, ohne
  Extraschritt.
- Einmaliger initialer Kopiervorgang als Teil der Implementierung, damit der aktuelle
  Stand sofort verfügbar ist (nicht erst ab dem nächsten Bump).
- Zur Laufzeit gelesen über `Bundle.main.url(forResource: "CHANGELOG", withExtension:
  "md")`.

### C) Parser: `ChangelogParser.swift`

Neuer, reiner (kein I/O, kein State) Parser-Typ unter `Feedivo/Services/` (bzw.
passendem bestehenden Ordner für reine Werttyp-Logik):

```swift
struct ChangelogEntry {
    let version: String   // z. B. "1.0 (28)"
    let date: String      // z. B. "2026-08-07", roher String aus der Überschrift
    let bullets: [String] // Aufzählungspunkte, führendes "- " entfernt
}

enum ChangelogParser {
    static func parse(_ markdown: String) -> [ChangelogEntry]
}
```

Erkennt Überschriften im Format `## [Version] - Datum` (identisches Regex-/Scan-Muster
wie das bereits bestehende `awk`-Skript in `create_github_release.sh`, das denselben
obersten Eintrag extrahiert) und sammelt alle folgenden `- `-Zeilen bis zur nächsten
`##`-Überschrift oder Dateiende. Unbekannte/fehlerhafte Zeilen werden übersprungen statt
zu crashen (Konsistenz mit dem bestehenden `UpdateReleaseNoteCategorizer`-Fallback-
Prinzip: robuste Degradierung statt Absturz bei einem Formatierungsausreißer).

Isoliert unit-testbar mit eingebettetem Beispiel-Markdown-String (kein Bundle-Zugriff im
Test nötig).

### D) Fenster: `VersionHistoryWindowView.swift`

Neue `View`, registriert als eigene `Window`-Scene in `FeedivoApp.swift` (nach dem
`CleanupHistoryWindowView`-Vorbild direkt darunter eingefügt):

```swift
Window(L10n.versionHistoryWindowTitle, id: VersionHistoryWindowView.windowID) {
    VersionHistoryWindowView()
        .environment(\.locale, appLanguage.locale)
        .environment(\.interfaceTextSize, interfaceTextSize)
        .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        .preferredColorScheme(appAppearance.colorScheme)
}
.defaultSize(width: 480, height: 560)
```

Lädt beim `.onAppear` die gebündelte `CHANGELOG.md`, parst sie über `ChangelogParser`,
zeigt die **ersten 15 Einträge** (Datei ist neueste-zuerst sortiert, kein Re-Sort nötig)
in einer scrollbaren Liste:

- Pro Version: Kopfzeile mit Versionsnummer (fett) + Datum (sekundär), darunter die
  Bullet-Punkte als einfache `Text`-Liste (kein Markdown-Inline-Parsing nötig — die
  Quelle enthält keine Links/Fettungen, reine Sätze in einfacher Sprache).
- Am Ende der Liste, nur sichtbar falls mehr als 15 Einträge geparst wurden: ein
  `Link` "Ältere Versionen auf GitHub ansehen" → `https://github.com/martinfelder/
  feedivo-mac/blob/main/CHANGELOG.md`.
- Fehlt die Bundle-Ressource oder liefert der Parser 0 Einträge (sollte praktisch nie
  vorkommen, da die Kopie beim Build immer aktuell ist): einfacher Leerzustand-Text,
  kein Absturz.

Kein neuer `@Observable`-State nötig, keine Datenbankanbindung (rein dateibasiert,
unabhängig von SQLite) — einfacher als `CleanupHistoryWindowView`, das per
`SQLiteDataInvalidation` live nachlädt (hier nicht nötig, da sich der Inhalt nur mit
einem neuen App-Build ändert).

## Fehlerbehandlung

- Bundle-Ressource fehlt (sollte durch den Build-Prozess ausgeschlossen sein, aber
  defensiv abgesichert): leere Liste → Leerzustand-Text statt Absturz.
- Parser trifft auf unerwartetes Format (z. B. eine Zeile ohne erkennbares Präfix):
  Zeile wird ignoriert, Rest der Datei normal weiterverarbeitet.

## Tests

- `ChangelogParserTests`: mehrere Versionsblöcke, leere Datei, Datei ohne
  `<!-- versions -->`-Marker, Bullet-Zeilen mit/ohne führendes `- `, Grenzfall "genau 15
  vs. mehr als 15 Einträge" (Truncation-Logik, falls im Parser statt in der View
  umgesetzt — Entscheidung fällt beim Implementieren, siehe Plan).
- Kein UI-Test nötig (kein computer-use für native macOS-Apps verfügbar) — manuelle
  Live-Verifikation nach Implementierung: GitHub-Link öffnet Browser, Versionshistorie-
  Fenster zeigt echte Einträge, "Ältere Versionen"-Link erscheint nur bei > 15 Einträgen.

## Offene, bewusst nicht behandelte Punkte

- Keine Suche/Filterung im Versionshistorie-Fenster (YAGNI für eine reine
  Nachschlage-Liste).
- Keine Kategorisierung nach Neu/Fehlerbehebung/Verbesserung (der bereits vorhandene,
  aber unbenutzte `UpdateReleaseNoteCategorizer` passt nicht, da er englische
  Commit-Präfixe wie `feat:`/`fix:` erwartet, `CHANGELOG.md` aber bereits in einfacher
  deutscher Sprache formulierte Bullets ohne diese Präfixe enthält — reine Textliste
  reicht für den Zweck "Nachschlagen, was sich geändert hat").
