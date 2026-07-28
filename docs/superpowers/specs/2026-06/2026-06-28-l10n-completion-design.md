# L10n-Abschluss — Design-Spec

**Datum:** 2026-06-28
**Status:** genehmigt (Brainstorming 2026-06-28)
**Ziel:** L10n-Abschluss für Feedivo macOS — Plural-Varianten, echte hardcoded-Literal-Lücken, und Lokalisierung der 8 Default-SmartFolder-Namen.

## Entscheidungen (aus Brainstorming)

- **Sprachen:** DE (Source) + EN + FR + IT, AI-generierte konkrete Übersetzungswerte; Nutzer reviewt stichprobenartig.
- **Scope:** 23 Count-Strings → Plural-Varianten; 67 hardcoded Literale (nur echte Lücken, s. Task 0); 8 Default-SmartFolder-Namen lokalisiert. Custom-Ordner-Namen bleiben unlokalisiert (Nutzerdaten).
- **Default-Namen:** Ansatz 1 — neues `defaultKey: String?`-Feld, Display lokalisiert, Restore matcht nach `defaultKey` (repariert `isDefault`-Invariant als Bonus), einmalige Migration, Editor-Name-Feld für Defaults deaktiviert, Test assertet `defaultKey`.
- **Default-Namen nicht im Scope (vom Nutzer korrigiert):** frühere „C"-Entscheidung wurde vom Nutzer zurückgenommen — Defaults sollen lokalisiert werden.

## Abschnitt 1 — Scope-Klärung (Inventur, Task 0)

`sourceLanguage = "de"` + String Catalogs → Xcode auto-extrahiert `Text("…")`-View-Literale als Keys. Viele der 67 Literale sind bereits im Katalog (mit EN/FR/IT) → keine Lücke.

Echte Lücken:
- **(a) Plain-`String`-Zuweisungen in ViewModels** (`errorMessage = "…"`, Status-Texte) — nicht auto-extrahiert, echter Bypass.
- **(b) View-`Text("…")`-Literale ohne Katalogeintrag** (oder nur DE) — Lücke.

Task 0 liefert eine Liste je Literal: View-Text vs. Plain-String + Katalog-Status (vorhanden/fehlend/Sprachen). Nur echte Lücken werden angefasst; bereits lokalisierte als „keine Aktion" dokumentiert.

## Abschnitt 2 — Plural-Varianten (23 Count-Strings)

Pro Count-String (`%lld …`) im Katalog `variations.plural` je Sprache anlegen (Xcode generiert CLDR-Kategorien automatisch):
- EN: `one` (n=1) / `other`
- FR: `one` (n=0,1) / `other` (≥2)
- IT: `one` (n=1) / `many`
- DE: `one` / `other`

Werte AI-generiert, Nutzer reviewst. Code-Nutzung via `LocalizedStringKey`/`String(localized:)` mit `%lld`-Interpolation; Swift wählt automatisch die richtige Plural-Variante.

## Abschnitt 3 — Default-SmartFolder-Namen (`defaultKey`)

- **Modell:** `SmartFolder` bekommt `var defaultKey: String? = nil` (Optional+Default → CloudKit-safe). 8 Defaults: `all`, `unread`, `starred`, `today`, `hidden`, `archived`, `thisWeek`, `saved`; Custom = `nil`. `defaultFolders` setzt `defaultKey` direkt.
- **Anzeige:** `var localizedDisplayName: String` — `defaultKey != nil` → `switch` → `String(localized: "smartFolder.default.<key>")`, sonst `folder.name`. Views (`SidebarView:493`, `SmartFolderSettingsView:233,299`) zeigen `localizedDisplayName` statt `name`.
- **Restore:** `restoreDefaultFolders` matcht nach `defaultKey` (statt Name) → repariert `isDefault`-Invariant.
- **Migration (einmalig, App-Start, bestehende Backfill-Pipeline):** Defaults mit `isDefault==true` per deutschem Namen → `defaultKey` backfillen (8 Namen bekannt).
- **Editor:** Name-Feld für Defaults deaktiviert (`SmartFolderEditorView:291`).
- **Test:** `restoreDefaultFoldersLegtAlleVordefiniertenIntelligentenOrdnerAn` assertet künftig `map(\.defaultKey)` statt deutsche Namen; neuer Test für `localizedDisplayName`.

## Abschnitt 4 — Arbeitsweise & Zugriff

- **`L10n.swift`-Accessor** (bestehendes Muster, zwei Flavors): `LocalizedStringKey("…")` für View-Kontexte, `String(localized: "…")` für Plain-String-Kontexte. Neue Keys für echte Literale + 8 Default-Namen.
- **xcstrings-Einträge:** je Key `de`/`en`/`fr`/`it` mit AI-generierten Werten (state `translated`), Plural-Strings mit `variations.plural`.
- **Batching:** Tasks nach Datei/Cluster (FirstRun, OPML, SmartFolderSettings, SmartFolderEditor, RuleSettings, Sidebar + ViewModels für Plain-Strings), je eigener TDD-Commit.
- **TDD:** Plural-Variante pro String (1 vs. many) für DE/EN; `localizedDisplayName`-Test; `defaultKey`-Restore-Test; Inventur-Ergebnis als Assertion-Dokumentation.

## Abschnitt 5 — Verifikation

- Build + `FeedivoTests` grün (`-only-testing:FeedivoTests`, wg. vorbestehend flaky `FeedivoUITests/testExample` + `importOPMLFeedsSpeichertGewaehltesAktualisierungsintervall`).
- Manuelle Sprachumschaltung via Scheme-Argument (`-AppleLanguages (en)` etc.) für Stichproben.
- Kein `.pbxproj`-Edit (xcstrings + neue `.swift` auto-inkludiert via `PBXFileSystemSynchronizedRootGroup`).
- Kommentare deutsch (CLAUDE.md).
- Keine nutzersichtbare Verhaltensänderung außer: Default-Ordner-Namen zeigen lokalisiert; Custom-Ordner unangetastet; Plural-Anzeige korrekt.

## Global Constraints (bindend)

- SwiftData `@Model`-Properties Optional-oder-Default (CloudKit) — `defaultKey: String? = nil` erfüllt das.
- Kommentare auf Deutsch.
- Kein `.pbxproj`-Edit.
- Verhaltenserhalt: Custom-Ordner-Namen und -Sortierung bleiben; Default-Sortierung bleibt stabil (nach `sortOrder`/deutschem Namen, nur Anzeige lokalisiert — Reihenfolge sprachunabhängig, bewusst akzeptiert).

## Offen / bewusst akzeptiert

- Default-Sortierung bleibt nach DB-`name` (deutsch), nur Anzeige lokalisiert → Reihenfolge sprachunabhängig. Sauberer wäre lokalisierte Sortierung, YAGNI hier.
- FR/IT AI-Qualität ohne Native-Review — Nutzer spot-review.
- `isDefault`-Invariant wird durch `defaultKey`-Restore-Match mitrepariert (Bonus, kein separater Task nötig).

## Build/Test-Befehle

- Build: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build`
- Tests: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test -only-testing:FeedivoTests`