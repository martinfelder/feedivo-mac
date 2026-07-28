# L10n-Abschluss Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** L10n-Abschluss für Feedivo macOS — Plural-Varianten für 24 Count-Strings, Lokalisierung echter hardcoded Literale (6 Datei-Cluster + ViewModel-Plain-Strings) und Lokalisierung der 8 Default-SmartFolder-Namen via `defaultKey`.

**Architecture:** Drei Stränge: (1) neues `defaultKey: String?`-Feld am `SmartFolder`-Modell mit `localizedDisplayName`-Accessor + Migration des Default-Namen-Matchings; (2) `variations.plural`-Einträge je Count-String im String-Catalog; (3) Ersatz hardcoded deutscher Literale durch `L10n`-Accessoren + neue xcstrings-Einträge. Ein Python-Injektions-Skript (`tools/l10n_inject.py`) übernimmt das deterministische Schreiben der xcstrings-Einträge aus TSV-Tabellen, damit Übersetzungen kompakt als echte Werte (keine Platzhalter) im Plan stehen.

**Tech Stack:** SwiftUI, SwiftData (`@Model`), String-Catalogs (`.xcstrings`, Source-Language `de`), Swift Testing (`@Test`/`#expect`), Python 3 (nur Build-Werkzeug, kein Runtime-Code).

## Global Constraints

- Source-Language `de`; Zielsprachen DE/EN/FR/IT, AI-generierte konkrete Werte, state `translated`.
- SwiftData `@Model`-Properties Optional-oder-Default (CloudKit) — `defaultKey: String? = nil` erfüllt das.
- Kommentare auf Deutsch (CLAUDE.md).
- Kein `.pbxproj`-Edit — xcstrings + neue `.swift` werden via `PBXFileSystemSynchronizedRootGroup` auto-inkludiert; `tools/l10n_inject.py` lebt außerhalb des Target-Ordners.
- Verhaltenserhalt: Custom-Ordner-Namen und -Sortierung bleiben; Default-Sortierung bleibt nach DB-`name` (deutsch), nur Anzeige lokalisiert — Reihenfolge sprachunabhängig, bewusst akzeptiert.
- Keine nutzersichtbare Verhaltensänderung außer: Default-Ordner-Namen lokalisiert, Custom-Ordner unangetastet, Plural-Anzeige korrekt.
- Build: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build`
- Tests: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test -only-testing:FeedivoTests` (UI-Tests wg. flaky `FeedivoUITests/testExample` + `importOPMLFeedsSpeichertGewaehltesAktualisierungsintervall` ausgeschlossen).
- Branch: `refactor/l10n-completion` (existiert).

---

## File Structure

**Neue Dateien:**
- `tools/l10n_inject.py` — Build-Werkzeug: injiziert plain- und plural-Tabellen (TSV) in `Localizable.xcstrings` (idempotent, sortiert Keys).
- `docs/superpowers/l10n/inventar.md` — Inventurergebnis aus Task 0 (Assertion-Dokumentation, verbindlich für Tasks 3–8).

**Modifikation:**
- `Feedivo/Models/SmartFolder.swift` — `defaultKey`-Feld + `localizedDisplayName`.
- `Feedivo/ViewModels/SmartFolderViewModel.swift` — `defaultFolders` setzen `defaultKey`; `restoreDefaultFolders` matcht nach `defaultKey`; `foldersSortedWithDefaultsFirst` sortiert nach `defaultKey`.
- `Feedivo/App/FeedivoApp.swift` — Migration im App-Start-Backfill (`restoreDefaultSmartFoldersIfNeeded` ruft neuen Backfill auf).
- `Feedivo/Services/SmartFolderDefaultKeyBackfillService.swift` (neu) — einmalige Migration, UserDefaults-Guard analog `FeedUnreadCountBackfillService`.
- `Feedivo/Views/Sidebar/SidebarView.swift` — hardcoded Literale → `L10n`; `smartFolder.name` → `localizedDisplayName`.
- `Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift` — Literale → `L10n`; `folder.name` → `localizedDisplayName`; Default-Erkennung via `defaultKey`.
- `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift` — Literale → `L10n`; Name-Feld für Defaults deaktiviert.
- `Feedivo/Views/Rules/RuleSettingsView.swift` — Literale → `L10n`.
- `Feedivo/Views/FirstRun/FirstRunWizardView.swift` — Plain-String-Computed-Properties + `Text`-Literale → `L10n`.
- `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift` — Literale → `L10n`.
- `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift` — Plain-String-Properties + Filter-Titel → `L10n` (`String(localized:)`).
- `Feedivo/Resources/L10n.swift` — neue Accessoren (plain + Keys für Default-Namen).
- `Feedivo/Resources/Localizable.xcstrings` — neue Keys, Plural-Varianten (via Skript).
- `FeedivoTests/SmartFolderViewModelTests.swift` — Test assertet `defaultKey`; neuer `localizedDisplayName`-Test.

**Verantwortlichkeiten:** Jeder Cluster-Task bündelt seine L10n-Accessor-Zeilen + xcstrings-Tabelle(n) + View-Edits in einem Commit. TDD nur wo Test-bar (Task 1); Tasks 3–8 sind Edit+Build-Verifikation je Cluster.

---

## Werkzeug-Vereinbarung: `tools/l10n_inject.py`

Alle Cluster-Tasks injizieren xcstrings-Einträge über dasselbe Skript, statt JSON per Hand zu schreiben. Das Skript ist in Task 0 zu erstellen und von allen späteren Tasks unverändert wiederzuverwenden. Tabellen sind TSV (Tab-getrennt), Kopfzeile beschreibt die Spalten.

**Plain-Modus** (`--mode plain --table plain.tsv`): Spalten `key<TAB>de<TAB>en<TAB>fr<TAB>it`. Schreibt je Sprache `localizations.<lang>.stringUnit.{state:"translated", value:<wert>}`. Bestehende Werte werden überschrieben (idempotent für gleiche Werte).

**Plural-Modus** (`--mode plural --table plural.tsv`): Spalten `key<TAB>de_one<TAB>de_other<TAB>en_one<TAB>en_other<TAB>fr_one<TAB>fr_other<TAB>it_one<TAB>it_many`. Schreibt je Sprache `localizations.<lang>.variations.plural.<kat>.stringUnit.{state,value}`. CLDR-Kategorien je Spec fest im Skript: DE `one`/`other`, EN `one`/`other`, FR `one`/`other` (Xcode wendet FR `one` automatisch auf n=0,1 an), IT `one`/`many`. `stringUnit` (nicht-pluraler Wert) wird gelöscht sobald `variations.plural` existiert.

Keys werden nach dem Lauf alphabetisch sortiert; Datei bleibt pretty-gedruckt mit 2-Spaces und `ensure_ascii=False`.

---

### Task 0: Inventur + Injektions-Werkzeug

**Files:**
- Create: `tools/l10n_inject.py`
- Create: `docs/superpowers/l10n/inventar.md`

**Interfaces:**
- Produces: `l10n_inject.py` (CLI: `python3 tools/l10n_inject.py --mode {plain|plural} --table <file> [--xcstrings path]`); `inventar.md` als verbindliche Literale-Liste für Tasks 3–8.

- [ ] **Step 1: Injektions-Skript schreiben**

`tools/l10n_inject.py`:

```python
#!/usr/bin/env python3
"""xcstrings-Injektor für L10n-Abschluss. Siehe Plan Task 0."""
import argparse, csv, json, sys

DEFAULT_PATH = "Feedivo/Resources/Localizable.xcstrings"
LANGS = ["de", "en", "fr", "it"]
# CLDR-Plural-Kategorien je Sprache (Spec-Abschnitt 2).
PLURAL_CATS = {"de": ["one", "other"], "en": ["one", "other"],
               "fr": ["one", "other"], "it": ["one", "many"]}

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def save(path, doc):
    doc["strings"] = dict(sorted(doc["strings"].items()))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")

def inject_plain(doc, rows):
    for row in rows:
        key, de, en, fr, it = row["key"], row["de"], row["en"], row["fr"], row["it"]
        entry = doc["strings"].setdefault(key, {"localizations": {}})
        locs = entry.setdefault("localizations", {})
        for lang, val in zip(LANGS, [de, en, fr, it]):
            locs[lang] = unit(val)
        # Plural-Variationen ggf. entfernen, damit plain wieder kanonisch ist.
        for lang in LANGS:
            locs.get(lang, {}).pop("variations", None)

def inject_plural(doc, rows):
    cols = ["key", "de_one", "de_other", "en_one", "en_other",
            "fr_one", "fr_other", "it_one", "it_many"]
    for row in rows:
        key = row["key"]
        entry = doc["strings"].setdefault(key, {"localizations": {}})
        locs = entry.setdefault("localizations", {})
        vals = {lang: {cat: row[f"{lang}_{cat}"] for cat in PLURAL_CATS[lang]}
                for lang in LANGS}
        for lang in LANGS:
            loc = locs.setdefault(lang, {})
            loc.pop("stringUnit", None)  # plain-Wert entfernen, Plural ist kanonisch.
            variations = loc.setdefault("variations", {}).setdefault("plural", {})
            for cat in PLURAL_CATS[lang]:
                variations[cat] = unit(vals[lang][cat])

def read_tsv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["plain", "plural"], required=True)
    ap.add_argument("--table", required=True)
    ap.add_argument("--xcstrings", default=DEFAULT_PATH)
    args = ap.parse_args()
    doc = load(args.xcstrings)
    rows = read_tsv(args.table)
    if args.mode == "plain":
        inject_plain(doc, rows)
    else:
        inject_plural(doc, rows)
    save(args.xcstrings, doc)
    print(f"{args.mode}: {len(rows)} Keys injiziert -> {args.xcstrings}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Skript testen (Roundtrip)**

```bash
printf "key\tde\ten\tfr\tit\nzzz.test\tx\ty\tz\tw\n" > /tmp/plain_test.tsv
cp Feedivo/Resources/Localizable.xcstrings /tmp/xcstrings_backup.json
python3 tools/l10n_inject.py --mode plain --table /tmp/plain_test.tsv --xcstrings /tmp/xcstrings_backup.json
python3 -c "import json;d=json.load(open('/tmp/xcstrings_backup.json'));print(d['strings']['zzz.test']['localizations']['en']['stringUnit']['value'])"
```
Expected: `y`

- [ ] **Step 3: Inventar-Datei schreiben**

`docs/superpowers/l10n/inventar.md` — verbindliche Literale-Liste je Cluster. Jedes Literal: Datei:Zeile · Typ (View-Text/Plain-String) · deutscher Wert · neuer Key · Katalog-Status vor Task (vorhanden/fehlend). Die Listen pro Cluster sind in den jeweiligen Tasks 3–8 vollständig wiederholt; diese Datei bündelt sie als Assertion-Dokumentation laut Spec. Inhalt (gekürzt auf Struktur + Gesamtzahl; die Einzelzeilen werden in Tasks 3–8 angelegt und hier nachgetragen):

```markdown
# L10n-Inventar (Task 0)

> Verbindlich für Tasks 3–8. Legt je Literal fest: Key, DE-Source-Wert, Typ,
> und ob der Key im Katalog vor Task-Ausführung existierte.

## Cluster Sidebar (SidebarView.swift): 9 Literale (8 neu + 1 bestehend)
- 110 confirmationDialog „Intelligenten Ordner löschen“ -> sidebar.smartFolder.deleteConfirm [fehlt]
- 121 Button „Löschen“ -> common.delete [fehlt]
- 238 Section „Intelligente Ordner“ -> sidebar.smartFilters.section [bestehend: L10n.sidebarSmartFiltersSection]
- 241 actionHelp „Intelligenten Ordner erstellen“ -> sidebar.smartFolder.create [fehlt]
- 249 „Keine intelligenten Ordner“ -> sidebar.smartFolders.empty [fehlt]
- 288 „Duplizieren“ -> common.duplicate [fehlt]
- 493 smartFolder.name -> localizedDisplayName (Task 1, kein Literal)
- 865 „Dieser Feed liefert aktuell keine Artikel für die Vorschau.“ -> sidebar.feedPreview.empty [fehlt]
- 870 „Letzte Artikel“ -> sidebar.feedPreview.recent [fehlt]
- 934 „Abonnieren“ -> sidebar.subscribe [fehlt]

## Cluster SmartFolderSettings (10 neu, 1 bestehend)
… (vollständige Liste siehe Task 4) …

## Cluster SmartFolderEditor (15 neu) — siehe Task 5
## Cluster RuleSettings (7 neu) — siehe Task 6
## Cluster FirstRun (Plain + View) — siehe Task 7
## Cluster OPMLImportReview — siehe Task 8
## Cluster OPMLImportPreviewController (Plain-String) — siehe Task 9
## Plural-Strings (24) — siehe Task 2

Gesamt echte Lücken: 67 Literale + 24 Plural-Strings + 8 Default-Namen (Task 1).
```

(Im Verlauf von Tasks 3–8 werden die konkreten Zeilen hier ergänzt; für die Ausführung sind die in den Tasks wiederholten Tabellen maßgeblich.)

- [ ] **Step 4: Commit**

```bash
git add tools/l10n_inject.py docs/superpowers/l10n/inventar.md
git commit -m "L10n Task 0: Inventar + xcstrings-Injektionswerkzeug"
```

---

### Task 1: `defaultKey`-Modell + `localizedDisplayName` + Migration (TDD)

**Files:**
- Modify: `Feedivo/Models/SmartFolder.swift`
- Modify: `Feedivo/ViewModels/SmartFolderViewModel.swift`
- Create: `Feedivo/Services/SmartFolderDefaultKeyBackfillService.swift`
- Modify: `Feedivo/App/FeedivoApp.swift:170-175`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift:291` (Name-Feld deaktivieren)
- Test: `FeedivoTests/SmartFolderViewModelTests.swift`

**Interfaces:**
- Produces: `SmartFolder.defaultKey: String?`, `SmartFolder.localizedDisplayName: String`; `SmartFolderDefaultKeyBackfillService.backfillDefaultKeys(in:defaults:)`; Default-Keys: `all`, `unread`, `starred`, `today`, `hidden`, `archived`, `thisWeek`, `saved`.

- [ ] **Step 1: Test anpassen (assert `defaultKey` statt Namen) + neuen Test**

In `FeedivoTests/SmartFolderViewModelTests.swift` den bestehenden Test `restoreDefaultFoldersLegtAlleVordefiniertenIntelligentenOrdnerAn` ersetzen:

```swift
@MainActor
@Test func restoreDefaultFoldersLegtAlleVordefiniertenIntelligentenOrdnerAn() throws {
    let container = try ModelContainer(
        for: Feed.self, Article.self, Tag.self, Rule.self, RuleCondition.self,
        SmartFolder.self, SmartFolderCondition.self, FeedLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let viewModel = SmartFolderViewModel()

    viewModel.restoreDefaultFolders(existingFolders: [], context: context)

    let folders = try context.fetch(FetchDescriptor<SmartFolder>())
    // Restore matcht künftig nach defaultKey, nicht nach deutschem Namen.
    #expect(SmartFolderViewModel.sortedFolders(folders).map(\.defaultKey) == [
        "all", "unread", "starred", "today", "hidden", "archived", "thisWeek", "saved"
    ])
    #expect(folders.allSatisfy { folder in folder.isShownInSidebar })
    #expect(folders.allSatisfy { folder in folder.isDefault })

    let allArticlesFolder = try #require(folders.first { $0.defaultKey == "all" })
    #expect(allArticlesFolder.conditions.isEmpty)
    #expect(allArticlesFolder.iconName == "tray.full")
    #expect(allArticlesFolder.colorHex == "#3B82F6")

    let starredFolder = try #require(folders.first { $0.defaultKey == "starred" })
    #expect(starredFolder.conditions.first?.value == SmartFolderStatusValue.starred.rawValue)
    #expect(starredFolder.iconName == "star.fill")
    #expect(starredFolder.colorHex == "#F59E0B")
}

@MainActor
@Test func localizedDisplayNameLiefertLokalisiertenNamenFuerDefaults() throws {
    let defaultFolder = SmartFolder(name: "Alle Artikel", isDefault: true)
    defaultFolder.defaultKey = "all"
    let customFolder = SmartFolder(name: "Mein Ordner")

    // Custom-Namen bleiben unverändert; Default-Namen werden lokalisiert.
    #expect(customFolder.localizedDisplayName == "Mein Ordner")
    // Im DE-Source-Locale ergibt der Key den deutschen Source-Wert.
    let deLocale = Locale(identifier: "de")
    #expect(String(localized: "smartFolder.default.all", locale: deLocale) == defaultFolder.localizedDisplayName
            || defaultFolder.localizedDisplayName == "Alle Artikel")
}
```

Hinweis: Der zweite Branch sichert den Test gegen die Bundle-Auflösung ab — im Test-Kontext liefert `String(localized:)` den Source-Wert zurück, wenn keine Übersetzung gefunden wird. Da `smartFolder.default.all` DE-Wert „Alle Artikel“ erhält, stimmt beides.

- [ ] **Step 2: Test laufen lassen → RED**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SmartFolderViewModelTests/restoreDefaultFoldersLegtAlleVordefiniertenIntelligentenOrdnerAn test 2>&1 | tail -20
```
Expected: FAIL (`defaultKey` unbekannt / `.map(\.defaultKey)` kompiliert nicht).

- [ ] **Step 3: `defaultKey`-Feld + `localizedDisplayName` am Modell**

`Feedivo/Models/SmartFolder.swift` — nach `var isDefault: Bool = false` einfügen und init erweitern:

```swift
// Lokalisierung der 8 Default-Ordner: nil = Custom (Name unangetastet),
// gesetzt = Default (Anzeige via localizedDisplayName, Restore matcht hierauf).
// Optional+Default nil -> CloudKit-safe (CLAUDE.md).
var defaultKey: String? = nil
```

```swift
init(
    name: String,
    matchMode: RuleMatchMode = .all,
    isShownInSidebar: Bool = true,
    isDefault: Bool = false,
    sortOrder: Int = 0,
    iconName: String = "folder.badge.gearshape",
    colorHex: String = "#6B7280",
    defaultKey: String? = nil,
    conditions: [SmartFolderCondition] = []
) {
    self.id = UUID()
    self.name = name
    self.matchModeRaw = matchMode.rawValue
    self.isShownInSidebar = isShownInSidebar
    self.isDefault = isDefault
    self.sortOrder = sortOrder
    self.defaultKey = defaultKey
    self.iconNameRaw = SmartFolderAppearance.normalizedIconName(iconName)
    self.colorHexRaw = SmartFolderAppearance.normalizedColorHex(colorHex)
    self.conditions = conditions
}

// Anzeige-Name: Defaults lokalisiert, Custom = gespeicherter Name.
var localizedDisplayName: String {
    guard let defaultKey else { return name }
    switch defaultKey {
    case "all":       return String(localized: "smartFolder.default.all")
    case "unread":    return String(localized: "smartFolder.default.unread")
    case "starred":   return String(localized: "smartFolder.default.starred")
    case "today":     return String(localized: "smartFolder.default.today")
    case "hidden":    return String(localized: "smartFolder.default.hidden")
    case "archived":  return String(localized: "smartFolder.default.archived")
    case "thisWeek":  return String(localized: "smartFolder.default.thisWeek")
    case "saved":     return String(localized: "smartFolder.default.saved")
    default:          return name
    }
}
```

- [ ] **Step 4: `defaultFolders` setzen `defaultKey`, Restore matcht nach `defaultKey`**

In `Feedivo/ViewModels/SmartFolderViewModel.swift` jedes der 8 `SmartFolder(...)`-Literale in `defaultFolders` um `defaultKey:` ergänzen (Reihenfolge der Argumente egal; hier nur die ergänzten Zeilen gezeigt):

```swift
SmartFolder(name: "Alle Artikel", matchMode: .all, isDefault: true,
            iconName: "tray.full", colorHex: "#3B82F6", defaultKey: "all", conditions: [])
SmartFolder(name: "Ungelesen", matchMode: .all, isDefault: true,
            iconName: "circle.fill", colorHex: "#14B8A6", defaultKey: "unread",
            conditions: [SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.unread.rawValue)])
SmartFolder(name: "Mit Stern", matchMode: .all, isDefault: true,
            iconName: "star.fill", colorHex: "#F59E0B", defaultKey: "starred",
            conditions: [SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.starred.rawValue)])
SmartFolder(name: "Heute", matchMode: .all, isDefault: true,
            iconName: "calendar", colorHex: "#22C55E", defaultKey: "today",
            conditions: [SmartFolderCondition(field: .date, conditionOperator: .is, value: SmartFolderDateValue.today.rawValue)])
SmartFolder(name: "Ausgeblendet", matchMode: .all, isDefault: true,
            iconName: "eye.slash", colorHex: "#6B7280", defaultKey: "hidden",
            conditions: [SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.hidden.rawValue)])
SmartFolder(name: "Archiviert", matchMode: .all, isDefault: true,
            iconName: "archivebox", colorHex: "#8B5CF6", defaultKey: "archived",
            conditions: [SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.archived.rawValue)])
SmartFolder(name: "Diese Woche", matchMode: .all, isDefault: true,
            iconName: "calendar", colorHex: "#22C55E", defaultKey: "thisWeek",
            conditions: [SmartFolderCondition(field: .date, conditionOperator: .is, value: SmartFolderDateValue.thisWeek.rawValue)])
SmartFolder(name: "Gespeichert", matchMode: .any, isDefault: true,
            iconName: "bookmark", colorHex: "#F97316", defaultKey: "saved",
            conditions: [
                SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.starred.rawValue),
                SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.archived.rawValue)
            ])
```

`restoreDefaultFolders` matcht nach `defaultKey`:

```swift
func restoreDefaultFolders(existingFolders: [SmartFolder], context: ModelContext) {
    let existingDefaultKeys = Set(existingFolders.compactMap(\.defaultKey))
    var folders = Self.sortedFolders(existingFolders)
    let defaults = Self.defaultFolders

    for defaultFolder in defaults where !existingDefaultKeys.contains(defaultFolder.defaultKey ?? "") {
        defaultFolder.sortOrder = folders.count
        context.insert(defaultFolder)
        folders.append(defaultFolder)
    }

    normalizeSortOrder(in: foldersSortedWithDefaultsFirst(folders, defaults: defaults))
    save(context)
}
```

`foldersSortedWithDefaultsFirst` sortiert nach `defaultKey`:

```swift
private func foldersSortedWithDefaultsFirst(
    _ folders: [SmartFolder],
    defaults: [SmartFolder]
) -> [SmartFolder] {
    let defaultOrder = Dictionary(
        uniqueKeysWithValues: defaults.enumerated().map { index, folder in
            (folder.defaultKey ?? folder.name, index)
        }
    )
    let defaultFolders = folders
        .filter { (defaultOrder[$0.defaultKey ?? ""] ?? defaultOrder[$0.name]) != nil }
        .sorted { firstFolder, secondFolder in
            (defaultOrder[firstFolder.defaultKey ?? ""] ?? defaultOrder[firstFolder.name] ?? Int.max)
            < (defaultOrder[secondFolder.defaultKey ?? ""] ?? defaultOrder[secondFolder.name] ?? Int.max)
        }
    let customFolders = Self.sortedFolders(folders.filter {
        (defaultOrder[$0.defaultKey ?? ""] ?? defaultOrder[$0.name]) == nil
    })
    return defaultFolders + customFolders
}
```

- [ ] **Step 5: Default-Namen in xcstrings eintragen**

`tools/default_names.tsv`:

```
key	de	en	fr	it
smartFolder.default.all	Alle Artikel	All articles	Tous les articles	Tutti gli articoli
smartFolder.default.unread	Ungelesen	Unread	Non lus	Non letti
smartFolder.default.starred	Mit Stern	Starred	Favoris	Preferiti
smartFolder.default.today	Heute	Today	Aujourd'hui	Oggi
smartFolder.default.hidden	Ausgeblendet	Hidden	Masqués	Nascosti
smartFolder.default.archived	Archiviert	Archived	Archivés	Archiviati
smartFolder.default.thisWeek	Diese Woche	This week	Cette semaine	Questa settimana
smartFolder.default.saved	Gespeichert	Saved	Enregistrés	Salvati
```

```bash
python3 tools/l10n_inject.py --mode plain --table tools/default_names.tsv
```

- [ ] **Step 6: Migration-Service**

`Feedivo/Services/SmartFolderDefaultKeyBackfillService.swift`:

```swift
import Foundation
import SwiftData

enum SmartFolderDefaultKeyBackfillService {
    // Einmalig: bestehende Default-Ordner (isDefault==true) ohne defaultKey
    // nach deutschem Namen -> defaultKey backfillen. 8 bekannte Namen.
    private static let backfillDoneKey = "smartFolderDefaultKeyBackfillDone_v1"

    // Deutsche Source-Namen -> defaultKey (Spec-Abschnitt 3).
    private static let nameToKey: [String: String] = [
        "Alle Artikel": "all",
        "Ungelesen": "unread",
        "Mit Stern": "starred",
        "Heute": "today",
        "Ausgeblendet": "hidden",
        "Archiviert": "archived",
        "Diese Woche": "thisWeek",
        "Gespeichert": "saved"
    ]

    @MainActor
    @discardableResult
    static func backfillDefaultKeys(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> Int {
        guard !defaults.bool(forKey: backfillDoneKey) else { return 0 }

        let folders = try context.fetch(FetchDescriptor<SmartFolder>())
        var updatedCount = 0
        for folder in folders where folder.defaultKey == nil && folder.isDefault {
            if let key = nameToKey[folder.name] {
                folder.defaultKey = key
                updatedCount += 1
            }
        }
        if updatedCount > 0 {
            try context.save()
        }
        defaults.set(true, forKey: backfillDoneKey)
        return updatedCount
    }
}
```

- [ ] **Step 7: Migration am App-Start anhängen**

`Feedivo/App/FeedivoApp.swift` in `restoreDefaultSmartFoldersIfNeeded` (vor `restoreDefaultFolders`):

```swift
@MainActor
private func restoreDefaultSmartFoldersIfNeeded() {
    let context = modelContainer.mainContext
    _ = try? SmartFolderDefaultKeyBackfillService.backfillDefaultKeys(in: context)
    let folders = (try? context.fetch(FetchDescriptor<SmartFolder>())) ?? []
    SmartFolderViewModel().restoreDefaultFolders(existingFolders: folders, context: context)
}
```

- [ ] **Step 8: Editor-Name-Feld für Defaults deaktivieren**

`Feedivo/Views/SmartFolders/SmartFolderEditorView.swift` `basics` (Zeile 55–62):

```swift
private var basics: some View {
    VStack(alignment: .leading, spacing: 10) {
        if folder?.defaultKey != nil {
            // Default-Ordner-Namen sind lokalisiert (Task 1) und nicht
            // umbenanrbar — Custom-Ordner bleiben editierbar.
            Text(folder?.localizedDisplayName ?? "")
                .font(.body)
                .foregroundStyle(.secondary)
        } else {
            TextField(L10n.smartFolderFieldName, text: $name)
                .textFieldStyle(.roundedBorder)
        }

        Toggle(L10n.smartFolderShowInSidebar, isOn: $isShownInSidebar)
    }
}
```

(Accessoren `smartFolderFieldName`/`smartFolderShowInSidebar` werden in Task 5 angelegt; dieser Schritt setzt sie voraus. Reihenfolge: Task 5 vor diesem Schritt ausführen ODER die Literale hier inline als `LocalizedStringKey("smartFolder.field.name")` nutzen und Task 5 macht die Accessor-Konsolidierung. Im Zweifel Task 5 zuerst mergen.)

- [ ] **Step 9: Tests laufen lassen → GREEN**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SmartFolderViewModelTests test 2>&1 | tail -20
```
Expected: PASS (beide Tests grün).

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Models/SmartFolder.swift Feedivo/ViewModels/SmartFolderViewModel.swift \
  Feedivo/Services/SmartFolderDefaultKeyBackfillService.swift Feedivo/App/FeedivoApp.swift \
  Feedivo/Views/SmartFolders/SmartFolderEditorView.swift Feedivo/Resources/Localizable.xcstrings \
  FeedivoTests/SmartFolderViewModelTests.swift tools/default_names.tsv
git commit -m "L10n Task 1: defaultKey-Modell + localizedDisplayName + Migration + Editor-Sperre"
```

---

### Task 2: Plural-Varianten für 24 Count-Strings

**Files:**
- Modify: `Feedivo/Resources/Localizable.xcstrings` (via Skript)
- Create: `tools/plural.tsv`

**Interfaces:** — keine Code-Änderung; `%lld`-Interpolation wählt automatisch die Plural-Variante (Spec-Abschnitt 2).

- [ ] **Step 1: Plural-Tabelle schreiben**

`tools/plural.tsv` (Spalten: key, de_one, de_other, en_one, en_other, fr_one, fr_other, it_one, it_many). `%lld` bleibt in jedem Wert erhalten; `one` wird für n=1 (FR auch n=0) verwendet. Für Strings, deren Singular/Plural im Deutschen gleich klingen, sind `de_one`/`de_other` identisch.

```
key	de_one	de_other	en_one	en_other	fr_one	fr_other	it_one	it_many
reader.readingTime	ca. %lld Min. Lesezeit	ca. %lld Min. Lesezeit	approx. %lld min read	approx. %lld min read	env. %lld min de lecture	env. %lld min de lecture	circa %lld min di lettura	circa %lld min di lettura
feed.log.refreshed	Aktualisiert: %lld neuer Artikel	Aktualisiert: %lld neue Artikel	Refreshed: %lld new article	Refreshed: %lld new articles	Actualisé : %lld nouvel article	Actualisé : %lld nouveaux articles	Aggiornato: %lld nuovo articolo	Aggiornato: %lld nuovi articoli
notification.feedRefresh.summary.title	%lld neuer Artikel	%lld neue Artikel	%lld new article	%lld new articles	%lld nouvel article	%lld nouveaux articles	%lld nuovo articolo	%lld nuovi articoli
notification.rule.summary.title	%lld Treffer für „%2$@“	%lld Treffer für „%2$@“	%lld match for “%2$@”	%lld matches for “%2$@”	%lld correspondance pour « %2$@ »	%lld correspondances pour « %2$@ »	%lld corrispondenza per “%2$@”	%lld corrispondenze per “%2$@”
feed.error.refreshAllPartial	%lld Feed konnte nicht aktualisiert werden: %2$@	%lld Feeds konnten nicht aktualisiert werden: %2$@	%lld feed failed to refresh: %2$@	%lld feeds failed to refresh: %2$@	%lld flux n'a pas pu être actualisé : %2$@	%lld flux n'ont pas pu être actualisés : %2$@	%lld feed non aggiornato: %2$@	%lld feed non aggiornati: %2$@
feed.error.httpError	HTTP-Fehler %lld	HTTP-Fehler %lld	HTTP error %lld	HTTP error %lld	Erreur HTTP %lld	Erreur HTTP %lld	Errore HTTP %lld	Errore HTTP %lld
opml.import.result.message	%1$lld Feed importiert, %2$lld übersprungen	%1$lld Feeds importiert, %2$lld übersprungen	%1$lld feed imported, %2$lld skipped	%1$lld feeds imported, %2$lld skipped	%1$lld flux importé, %2$lld ignoré	%1$lld flux importés, %2$lld ignorés	%1$lld feed importato, %2$lld saltato	%1$lld feed importati, %2$lld saltati
opml.export.feedCount	%lld Feed	%lld Feeds	%lld feed	%lld feeds	%lld flux	%lld flux	%lld feed	%lld feed
opml.export.folderCount	%lld Ordner	%lld Ordner	%lld folder	%lld folders	%lld dossier	%lld dossiers	%lld cartella	%lld cartelle
opml.export.tagCount	%lld Tag	%lld Tags	%lld tag	%lld tags	%lld étiquette	%lld étiquettes	%lld etichetta	%lld etichette
opml.export.descriptionCount	%lld Beschreibung	%lld Beschreibungen	%lld description	%lld descriptions	%lld description	%lld descriptions	%lld descrizione	%lld descrizioni
settings.articleRetention.interval.days	%lld Tag	%lld Tage	%lld day	%lld days	%lld jour	%lld jours	%lld giorno	%lld giorni
settings.articleRetention.result	%lld Artikel entfernt	%lld Artikel entfernt	%lld article removed	%lld articles removed	%lld article supprimé	%lld articles supprimés	%lld articolo rimosso	%lld articoli rimossi
settings.automaticRefresh.interval.minutes	%lld Minute	%lld Minuten	%lld minute	%lld minutes	%lld minute	%lld minutes	%lld minuto	%lld minuti
settings.cache.limit.gigabytes	%lld GB	%lld GB	%lld GB	%lld GB	%lld Go	%lld Go	%lld GB	%lld GB
settings.cache.limit.megabytes	%lld MB	%lld MB	%lld MB	%lld MB	%lld Mo	%lld Mo	%lld MB	%lld MB
settings.feeds.deleteConfirmation.message	%lld Feed wird gelöscht	%lld Feeds werden gelöscht	%lld feed will be deleted	%lld feeds will be deleted	%lld flux sera supprimé	%lld flux seront supprimés	%lld feed verrà eliminato	%lld feed verranno eliminati
settings.feeds.selectedCount	%lld ausgewählt	%lld ausgewählt	%lld selected	%lld selected	%lld sélectionné	%lld sélectionnés	%lld selezionato	%lld selezionati
articleList.showRead.button	%lld gelesener Artikel	%lld gelesene Artikel	%lld read article	%lld read articles	%lld article lu	%lld articles lus	%lld articolo letto	%lld articoli letti
rule.applyExisting.result	%lld Aktion angewendet	%lld Aktionen angewendet	%lld action applied	%lld actions applied	%lld action appliquée	%lld actions appliquées	%lld azione applicata	%lld azioni applicate
ruleWizard.preview.matchCount	%lld Artikel passt	%lld Artikel passen	%lld article matches	%lld articles match	%lld article correspond	%lld articles correspondent	%lld articolo corrisponde	%lld articoli corrispondono
article.export.status.downloadingImage	Bild %lld wird geladen	Bilder %lld werden geladen	Image %lld downloading	Images %lld downloading	Image %lld en téléchargement	Images %lld en téléchargement	Immagine %lld in download	Immagini %lld in download
offline.error.unreachable	%lld Quelle nicht erreichbar	%lld Quellen nicht erreichbar	%lld source unreachable	%lld sources unreachable	%lld source inaccessible	%lld sources inaccessibles	%lld fonte non raggiungibile	%lld fonti non raggiungibili
```

Der 24. Count-String ist das View-Literal `"%lld Artikel passen aktuell zu diesem intelligenten Ordner."` (SmartFolderEditorView:250, bereits als Key im Katalog). Er bekommt Plural-Varianten über den gleichen Schlüssel; Tabelle umfasst ihn implizit nicht (da sein Key ein Leerzeichen/Satz ist). Stattdessen in Task 5 als `smartFolder.preview.matches`-Key neu angelgt; der bestehende Key-String wird durch einen benannten Key ersetzt und der alte Eintrag im selben Task aus dem Katalog entfernt.

- [ ] **Step 2: Injizieren**

```bash
python3 tools/l10n_inject.py --mode plural --table tools/plural.tsv
```

- [ ] **Step 3: Stichproben-Verifikation der Plural-Struktur**

```bash
python3 -c "
import json
d=json.load(open('Feedivo/Resources/Localizable.xcstrings'))
e=d['strings']['feed.log.refreshed']['localizations']
print('DE other:', e['de']['variations']['plural']['other']['stringUnit']['value'])
print('EN one :', e['en']['variations']['plural']['one']['stringUnit']['value'])
print('FR one :', e['fr']['variations']['plural']['one']['stringUnit']['value'])
print('IT many:', e['it']['variations']['plural']['many']['stringUnit']['value'])
"
```
Expected: `Aktualisiert: %lld neue Artikel` / `Refreshed: %lld new article` / `Actualisé : %lld nouvel article` / `Aggiornato: %lld nuovi articoli`.

- [ ] **Step 4: Build prüfen**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add tools/plural.tsv Feedivo/Resources/Localizable.xcstrings
git commit -m "L10n Task 2: Plural-Varianten für 24 Count-Strings"
```

---

### Task 3: Cluster Sidebar (SidebarView.swift)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift` (neue Accessoren)
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Create: `tools/sidebar.tsv`

**Interfaces:** — konsumiert `SmartFolder.localizedDisplayName` (Task 1).

- [ ] **Step 1: L10n-Accessoren anlegen**

In `Feedivo/Resources/L10n.swift` (bei den Sidebar-Accessoren, nach `sidebarSmartFiltersSection`):

```swift
static let sidebarSmartFoldersSection = LocalizedStringKey("sidebar.smartFolders.section")
static let sidebarSmartFoldersEmpty = LocalizedStringKey("sidebar.smartFolders.empty")
static let sidebarSmartFolderCreate = LocalizedStringKey("sidebar.smartFolder.create")
static let sidebarSmartFolderDelete = LocalizedStringKey("sidebar.smartFolder.delete")
static let sidebarSmartFolderDuplicate = LocalizedStringKey("sidebar.smartFolder.duplicate")
static let sidebarFeedPreviewEmpty = LocalizedStringKey("sidebar.feedPreview.empty")
static let sidebarFeedPreviewRecent = LocalizedStringKey("sidebar.feedPreview.recent")
static let sidebarSubscribe = LocalizedStringKey("sidebar.subscribe")
static let commonDelete = LocalizedStringKey("common.delete")
static let commonDuplicate = LocalizedStringKey("common.duplicate")
```

(Hinweis: `sidebarSmartFiltersSection` zeigt auf den bestehenden Key `sidebar.smartFilters.section`. Der Sektions-Titel „Intelligente Ordner“ wird ebenfalls auf `sidebar.smartFolders.section` umgestellt; deshalb neuer paralleler Key, dessen DE-Wert identisch ist. Beide Keys behalten, um bestehende Nutzersysteme nicht zu stören — ist hier OK, da der alte Key nirgends mehr referenziert wird nach diesem Task.)

- [ ] **Step 2: xcstrings-Tabelle injizieren**

`tools/sidebar.tsv`:

```
key	de	en	fr	it
sidebar.smartFolders.section	Intelligente Ordner	Smart folders	Dossiers intelligents	Cartelle smart
sidebar.smartFolders.empty	Keine intelligenten Ordner	No smart folders	Aucun dossier intelligent	Nessuna cartella smart
sidebar.smartFolder.create	Intelligenten Ordner erstellen	Create smart folder	Créer un dossier intelligent	Crea cartella smart
sidebar.smartFolder.delete	Intelligenten Ordner löschen	Delete smart folder	Supprimer le dossier intelligent	Elimina cartella smart
sidebar.smartFolder.duplicate	Duplizieren	Duplicate	Dupliquer	Duplica
sidebar.feedPreview.empty	Dieser Feed liefert aktuell keine Artikel für die Vorschau.	This feed currently provides no preview articles.	Ce flux ne fournit actuellement aucun article d'aperçu.	Questo feed non fornisce articoli di anteprima.
sidebar.feedPreview.recent	Letzte Artikel	Recent articles	Articles récents	Articoli recenti
sidebar.subscribe	Abonnieren	Subscribe	S'abonner	Iscriviti
common.delete	Löschen	Delete	Supprimer	Elimina
common.duplicate	Duplizieren	Duplicate	Dupliquer	Duplica
```

```bash
python3 tools/l10n_inject.py --mode plain --table tools/sidebar.tsv
```

- [ ] **Step 3: View-Edits in SidebarView.swift**

```swift
// Zeile 110: confirmationDialog
confirmationDialog(
    L10n.sidebarSmartFolderDelete,
    isPresented: Binding(
        get: { smartFolderPendingDeletion != nil },
        set: { isPresented in
            if !isPresented {
                smartFolderPendingDeletion = nil
            }
        }
    ),
    presenting: smartFolderPendingDeletion
) { smartFolder in
    Button(L10n.commonDelete, role: .destructive) {

// Zeile 238-242: smartFoldersSection Header
CollapsibleSidebarSection(
    title: L10n.sidebarSmartFoldersSection,
    isCollapsed: $isSmartFoldersCollapsed,
    actionSystemImage: "plus",
    actionHelp: String(localized: "sidebar.smartFolder.create")
) {

// Zeile 249: leerer Zustand
Text(L10n.sidebarSmartFoldersEmpty)

// Zeile 288: Duplizieren-Label
Label(L10n.commonDuplicate, systemImage: "plus.square.on.square")

// Zeile 493 (SmartFolderSidebarRow): Default-Namen lokalisiert
Text(smartFolder.localizedDisplayName)

// Zeile 865: Feed-Vorschau leer
Text(L10n.sidebarFeedPreviewEmpty)

// Zeile 870: Letzte Artikel
Text(L10n.sidebarFeedPreviewRecent)

// Zeile 934: Abonnieren
selectedFeedURL == nil ? L10n.feedDiscoverySearchButton : L10n.sidebarSubscribe
```

(`primaryButtonTitle` ist `LocalizedStringKey`; `L10n.sidebarSubscribe` ist `LocalizedStringKey` — Typ passt. `feedDiscoverySearchButton` ist ebenfalls `LocalizedStringKey`.)

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Views/Sidebar/SidebarView.swift \
  Feedivo/Resources/Localizable.xcstrings tools/sidebar.tsv
git commit -m "L10n Task 3: Sidebar-Cluster (9 Literale + Default-Namen)"
```

---

### Task 4: Cluster SmartFolderSettings (SmartFolderSettingsView.swift)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift`
- Create: `tools/smart_folder_settings.tsv`

- [ ] **Step 1: L10n-Accessoren**

```swift
static let smartFolderSettingsTitle = LocalizedStringKey("smartFolder.settings.title")
static let smartFolderSettingsDescription = LocalizedStringKey("smartFolder.settings.description")
static let smartFolderRestoreDefaults = LocalizedStringKey("smartFolder.restoreDefaults")
static let smartFolderNewFolder = LocalizedStringKey("smartFolder.newFolder")
static let smartFolderListHeaderOrder = LocalizedStringKey("smartFolder.listHeader.order")
static let smartFolderListHeaderSidebar = LocalizedStringKey("smartFolder.listHeader.sidebar")
static let smartFolderListHeaderName = LocalizedStringKey("smartFolder.listHeader.name")
static let smartFolderListHeaderConditions = LocalizedStringKey("smartFolder.listHeader.conditions")
static let smartFolderListHeaderMatches = LocalizedStringKey("smartFolder.listHeader.matches")
static let smartFolderShowInSidebar = LocalizedStringKey("smartFolder.showInSidebar")
static let smartFolderStandardFolder = LocalizedStringKey("smartFolder.standardFolder")
static let smartFolderCustomFolder = LocalizedStringKey("smartFolder.customFolder")
static let smartFolderDragToSort = LocalizedStringKey("smartFolder.dragToSort")
```

- [ ] **Step 2: xcstrings-Tabelle**

`tools/smart_folder_settings.tsv`:

```
key	de	en	fr	it
smartFolder.settings.empty	Keine intelligenten Ordner	No smart folders	Aucun dossier intelligent	Nessuna cartella smart
smartFolder.settings.title	Intelligente Ordner	Smart folders	Dossiers intelligents	Cartelle smart
smartFolder.settings.description	Dynamische Ordner werden in der Sidebar angezeigt und filtern Artikel automatisch.	Dynamic folders appear in the sidebar and filter articles automatically.	Les dossiers dynamiques s'affichent dans la barre latérale et filtrent les articles automatiquement.	Le cartelle dinamiche vengono mostrate nella barra laterale e filtrano gli articoli automaticamente.
smartFolder.restoreDefaults	Standardordner wiederherstellen	Restore default folders	Restaurer les dossiers par défaut	Ripristina cartelle predefinite
smartFolder.newFolder	Neuer Ordner	New folder	Nouveau dossier	Nuova cartella
smartFolder.listHeader.order	Reihenfolge	Order	Ordre	Ordine
smartFolder.listHeader.sidebar	Sidebar	Sidebar	Barre latérale	Barra laterale
smartFolder.listHeader.name	Name	Name	Nom	Nome
smartFolder.listHeader.conditions	Bedingungen	Conditions	Conditions	Condizioni
smartFolder.listHeader.matches	Treffer	Matches	Correspondances	Corrispondenze
smartFolder.showInSidebar	In Sidebar anzeigen	Show in sidebar	Afficher dans la barre latérale	Mostra nella barra laterale
smartFolder.standardFolder	Standardordner	Default folder	Dossier par défaut	Cartella predefinita
smartFolder.customFolder	Eigener Ordner	Custom folder	Dossier personnalisé	Cartella personalizzata
smartFolder.dragToSort	Zum Sortieren ziehen	Drag to sort	Glisser pour trier	Trascina per ordinare
```

```bash
python3 tools/l10n_inject.py --mode plain --table tools/smart_folder_settings.tsv
```

- [ ] **Step 3: View-Edits**

```swift
// Zeile 21: ContentUnavailableView
ContentUnavailableView(L10n.sidebarSmartFoldersEmpty, systemImage: "folder.badge.gearshape")

// Zeile 34: confirmationDialog
confirmationDialog(L10n.sidebarSmartFolderDelete, isPresented: ...

// Zeile 45: Löschen-Button
Button(L10n.commonDelete, role: .destructive) {

// Zeile 58: Header-Titel
Text(L10n.smartFolderSettingsTitle)

// Zeile 61: Beschreibung
Text(L10n.smartFolderSettingsDescription)

// Zeile 71: Standardordner wiederherstellen
Label(L10n.smartFolderRestoreDefaults, systemImage: "arrow.clockwise")

// Zeile 77: Neuer Ordner
Label(L10n.smartFolderNewFolder, systemImage: "plus")

// Zeile 141-150: ListHeader
Text(L10n.smartFolderListHeaderOrder).frame(width: 58, alignment: .leading)
Text(L10n.smartFolderListHeaderSidebar).frame(width: 60, alignment: .leading)
Text(L10n.smartFolderListHeaderName).frame(maxWidth: .infinity, alignment: .leading)
Text(L10n.smartFolderListHeaderConditions).frame(maxWidth: .infinity, alignment: .leading)
Text(L10n.smartFolderListHeaderMatches).frame(width: 72, alignment: .trailing)

// Zeile 217: Toggle-Label (labelsHidden, aber accessibility-relevant)
Toggle(L10n.smartFolderShowInSidebar, isOn: ...)

// Zeile 233: Name-Anzeige
Text(folder.localizedDisplayName)

// Zeile 238: Standard-/Eigener Ordner
Text(folder.defaultKey != nil ? L10n.smartFolderStandardFolder : L10n.smartFolderCustomFolder)

// Zeile 276: Duplizieren
Button(L10n.commonDuplicate, action: duplicate)

// Zeile 288: dragHandle help
.help(L10n.smartFolderDragToSort)

// Zeile 299: Drag-Preview-Name
Text(folder.localizedDisplayName)
```

- [ ] **Step 4: Build + Tests**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift \
  Feedivo/Resources/Localizable.xcstrings tools/smart_folder_settings.tsv
git commit -m "L10n Task 4: SmartFolderSettings-Cluster (13 Literale + Default-Namen)"
```

---

### Task 5: Cluster SmartFolderEditor (SmartFolderEditorView.swift)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift`
- Create: `tools/smart_folder_editor.tsv`

- [ ] **Step 1: L10n-Accessoren**

```swift
static let smartFolderEditorCreate = LocalizedStringKey("smartFolder.editor.create")
static let smartFolderEditorEdit = LocalizedStringKey("smartFolder.editor.edit")
static let smartFolderEditorDescription = LocalizedStringKey("smartFolder.editor.description")
static let smartFolderFieldName = LocalizedStringKey("smartFolder.field.name")
static let smartFolderAppearance = LocalizedStringKey("smartFolder.appearance")
static let smartFolderAppearanceIcon = LocalizedStringKey("smartFolder.appearance.icon")
static let smartFolderMatchModeOperator = LocalizedStringKey("smartFolder.matchMode.operator")
static let smartFolderMatchModeAll = LocalizedStringKey("smartFolder.matchMode.all")
static let smartFolderMatchModeAny = LocalizedStringKey("smartFolder.matchMode.any")
static let smartFolderConditions = LocalizedStringKey("smartFolder.conditions")
static let smartFolderConditionsEmpty = LocalizedStringKey("smartFolder.conditions.empty")
static let smartFolderConditionsAdd = LocalizedStringKey("smartFolder.conditions.add")
static let smartFolderOperatorAnd = LocalizedStringKey("smartFolder.operator.and")
static let smartFolderOperatorOr = LocalizedStringKey("smartFolder.operator.or")
static let smartFolderPreview = LocalizedStringKey("smartFolder.preview")
static let smartFolderPreviewMatches = LocalizedStringKey("smartFolder.preview.matches")
static let smartFolderSave = LocalizedStringKey("smartFolder.save")
```

- [ ] **Step 2: xcstrings-Tabelle**

`tools/smart_folder_editor.tsv`:

```
key	de	en	fr	it
smartFolder.editor.create	Intelligenten Ordner erstellen	Create smart folder	Créer un dossier intelligent	Crea cartella smart
smartFolder.editor.edit	Intelligenten Ordner bearbeiten	Edit smart folder	Modifier le dossier intelligent	Modifica cartella smart
smartFolder.editor.description	Dynamische Artikelansicht mit globalem UND/ODER-Operator.	Dynamic article view with global AND/OR operator.	Vue d'articles dynamique avec opérateur ET/OU global.	Vista articoli dinamica con operatore E/O globale.
smartFolder.field.name	Name	Name	Nom	Nome
smartFolder.appearance	Darstellung	Appearance	Apparence	Aspetto
smartFolder.appearance.icon	Icon	Icon	Icône	Icona
smartFolder.matchMode.operator	Operator	Operator	Opérateur	Operatore
smartFolder.matchMode.all	Erfülle alle Bedingungen	Match all conditions	Toutes les conditions	Tutte le condizioni
smartFolder.matchMode.any	Erfülle eine Bedingung	Match any condition	Une condition quelconque	Almeno una condizione
smartFolder.conditions	Bedingungen	Conditions	Conditions	Condizioni
smartFolder.conditions.empty	Ohne Bedingungen werden alle Artikel angezeigt.	Without conditions, all articles are shown.	Sans condition, tous les articles sont affichés.	Senza condizioni, vengono mostrati tutti gli articoli.
smartFolder.conditions.add	Bedingung hinzufügen	Add condition	Ajouter une condition	Aggiungi condizione
smartFolder.operator.and	UND	AND	ET	E
smartFolder.operator.or	ODER	OR	OU	O
smartFolder.preview	Live-Vorschau	Live preview	Aperçu en direct	Anteprima live
smartFolder.save	Speichern	Save	Enregistrer	Salva
```

Plural für `smartFolder.preview.matches` (ersetzt das View-Literal `%lld Artikel passen aktuell zu diesem intelligenten Ordner.`): separate Plural-Tabelle `tools/smart_folder_editor_plural.tsv`:

```
key	de_one	de_other	en_one	en_other	fr_one	fr_other	it_one	it_many
smartFolder.preview.matches	%lld Artikel passt aktuell zu diesem intelligenten Ordner.	%lld Artikel passen aktuell zu diesem intelligenten Ordner.	%lld article currently matches this smart folder.	%lld articles currently match this smart folder.	%lld article correspond actuellement à ce dossier intelligent.	%lld articles correspondent actuellement à ce dossier intelligent.	%lld articolo corrisponde attualmente a questa cartella smart.	%lld articoli corrispondono attualmente a questa cartella smart.
```

```bash
python3 tools/l10n_inject.py --mode plain --table tools/smart_folder_editor.tsv
python3 tools/l10n_inject.py --mode plural --table tools/smart_folder_editor_plural.tsv
# Bestehenden auto-extrahierten Key "%lld Artikel passen aktuell zu diesem intelligenten Ordner." entfernen:
python3 -c "
import json
p='Feedivo/Resources/Localizable.xcstrings'
d=json.load(open(p))
d['strings'].pop('%lld Artikel passen aktuell zu diesem intelligenten Ordner.', None)
json.dump(dict(sorted(d['strings'].items())) and d, open(p,'w',encoding='utf-8'), ensure_ascii=False, indent=2)
open(p,'a',encoding='utf-8').write('')
"
```

(Korrektur: der pop-Schritt muss die Datei neu sortiert schreiben — der Inline-Ausdruck oben ist fehlerträchtig. Stattdessen nachfolgenden Block verwenden:)

```bash
python3 - <<'PY'
import json
p='Feedivo/Resources/Localizable.xcstrings'
d=json.load(open(p, encoding='utf-8'))
d['strings'].pop('%lld Artikel passen aktuell zu diesem intelligenten Ordner.', None)
d['strings']=dict(sorted(d['strings'].items()))
with open(p,'w',encoding='utf-8') as f:
    json.dump(d,f,ensure_ascii=False,indent=2); f.write('\n')
PY
```

- [ ] **Step 3: View-Edits in SmartFolderEditorView.swift**

```swift
// Zeile 45: Header-Titel
Text(folder == nil ? L10n.smartFolderEditorCreate : L10n.smartFolderEditorEdit)

// Zeile 49: Beschreibung
Text(L10n.smartFolderEditorDescription)

// Zeile 57: Name-Placeholder (nur im Nicht-Default-Fall; Default-Sperre kommt aus Task 1 Step 8)
TextField(L10n.smartFolderFieldName, text: $name)

// Zeile 60: Toggle
Toggle(L10n.smartFolderShowInSidebar, isOn: $isShownInSidebar)

// Zeile 66: Darstellung
Text(L10n.smartFolderAppearance)

// Zeile 79: Icon-Picker
Picker(L10n.smartFolderAppearanceIcon, selection: $iconName) { ... }

// Zeile 111: Operator-Picker
Picker(L10n.smartFolderMatchModeOperator, selection: $matchMode) {
    Text(L10n.smartFolderMatchModeAll).tag(RuleMatchMode.all)
    Text(L10n.smartFolderMatchModeAny).tag(RuleMatchMode.any)
}

// Zeile 122: Bedingungen
Text(L10n.smartFolderConditions)

// Zeile 129: leerer Zustand
Text(L10n.smartFolderConditionsEmpty)

// Zeile 136: Bedingung hinzufügen
Label(L10n.smartFolderConditionsAdd, systemImage: "plus.circle")

// Zeile 150: UND/ODER
Text(matchMode == .all ? L10n.smartFolderOperatorAnd : L10n.smartFolderOperatorOr)

// Zeile 247: Live-Vorschau
Text(L10n.smartFolderPreview)

// Zeile 250: Treffer-Text -> String(localized:)-Format, Plural-Variante
Text(String.localizedStringWithFormat(String(localized: "smartFolder.preview.matches"), matchingCount))

// Zeile 278: Speichern
Button(L10n.smartFolderSave) { save() }
```

(`String.localizedStringWithFormat` wählt die korrekte Plural-Variante; `Text(String)` ist hier erlaubt, da der Wert dynamisch interpoliert wird.)

- [ ] **Step 4: Build + Tests**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Views/SmartFolders/SmartFolderEditorView.swift \
  Feedivo/Resources/Localizable.xcstrings tools/smart_folder_editor.tsv \
  tools/smart_folder_editor_plural.tsv
git commit -m "L10n Task 5: SmartFolderEditor-Cluster (17 Literale + 1 Plural)"
```

---

### Task 6: Cluster RuleSettings (RuleSettingsView.swift)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Views/Rules/RuleSettingsView.swift`
- Create: `tools/rule_settings.tsv`

- [ ] **Step 1: L10n-Accessoren**

```swift
static let ruleSettingsDescription = LocalizedStringKey("rule.settings.description")
static let ruleListHeaderOrder = LocalizedStringKey("rule.listHeader.order")
static let ruleListHeaderActive = LocalizedStringKey("rule.listHeader.active")
static let ruleListHeaderRule = LocalizedStringKey("rule.listHeader.rule")
static let ruleListHeaderAction = LocalizedStringKey("rule.listHeader.action")
static let ruleListHeaderMatches = LocalizedStringKey("rule.listHeader.matches")
static let ruleActionMissingTag = LocalizedStringKey("rule.action.missingTag")
static let ruleMoveUp = LocalizedStringKey("rule.moveUp")
static let ruleMoveDown = LocalizedStringKey("rule.moveDown")
```

- [ ] **Step 2: xcstrings-Tabelle**

`tools/rule_settings.tsv`:

```
key	de	en	fr	it
rule.settings.description	Regeln werden von oben nach unten angewendet.	Rules are applied top to bottom.	Les règles sont appliquées de haut en bas.	Le regole vengono applicate dall'alto al basso.
rule.listHeader.order	Reihenfolge	Order	Ordre	Ordine
rule.listHeader.active	Aktiv	Active	Actif	Attivo
rule.listHeader.rule	Regel	Rule	Règle	Regola
rule.listHeader.action	Aktion	Action	Action	Azione
rule.listHeader.matches	Treffer	Matches	Corrispondenze	Corrispondenze
rule.action.missingTag	Tag fehlt	Tag missing	Étiquette manquante	Etichetta mancante
rule.moveUp	Nach oben	Move up	Vers le haut	Su
rule.moveDown	Nach unten	Move down	Vers le bas	Giù
common.duplicate	Duplizieren	Duplicate	Dupliquer	Duplica
```

(`common.duplicate` ist bereits aus Task 3 injiziert — der Re-Inject ist idempotent; die Zeile darf bleiben.)

```bash
python3 tools/l10n_inject.py --mode plain --table tools/rule_settings.tsv
```

- [ ] **Step 3: View-Edits in RuleSettingsView.swift**

```swift
// Zeile 74: Header-Beschreibung
Text(L10n.ruleSettingsDescription)

// Zeile 161-170: ListHeader
Text(L10n.ruleListHeaderOrder).frame(width: 78, alignment: .leading)
Text(L10n.ruleListHeaderActive).frame(width: 44, alignment: .leading)
Text(L10n.ruleListHeaderRule).frame(maxWidth: .infinity, alignment: .leading)
Text(L10n.ruleListHeaderAction).frame(width: 150, alignment: .leading)
Text(L10n.ruleListHeaderMatches).frame(width: 72, alignment: .trailing)

// Zeile 249: Duplizieren
Button(L10n.commonDuplicate, action: duplicate)

// Zeile 265: help Nach oben
.help(L10n.ruleMoveUp)

// Zeile 271: help Nach unten
.help(L10n.ruleMoveDown)

// Zeile 298: Tag fehlt
Text(L10n.ruleActionMissingTag)
```

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Views/Rules/RuleSettingsView.swift \
  Feedivo/Resources/Localizable.xcstrings tools/rule_settings.tsv
git commit -m "L10n Task 6: RuleSettings-Cluster (8 Literale)"
```

---

### Task 7: Cluster FirstRun (FirstRunWizardView.swift)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Views/FirstRun/FirstRunWizardView.swift`
- Create: `tools/first_run.tsv`, `tools/first_run_plural.tsv`

Hinweis: FirstRun nutzt sowohl `Text(...)`-View-Literale (auto-extrahierbar) als auch Plain-`String`-Computed-Properties (`stepTitle`, `stepLead`, `primaryButtonTitle`, `filterButtonTitle`, `selectedCountText`, `previewSummaryText`, `importSummaryText`, `intervalTitle`, `FirstRunCompletionSummary.problemMessages`). Die Plain-Strings werden auf `String(localized:)`-Accessoren umgestellt; View-`Text`-Literale auf `LocalizedStringKey`-Accessoren.

- [ ] **Step 1: L10n-Accessoren (Plain + View)**

```swift
// Plain-String-Kontexte (String(localized:))
static let firstRunTitlebarTitle = String(localized: "firstRun.titlebar.title")
static let firstRunStepWelcomeTitle = String(localized: "firstRun.step.welcome.title")
static let firstRunStepAddFeedTitle = String(localized: "firstRun.step.addFeed.title")
static let firstRunStepImportOPMLTitle = String(localized: "firstRun.step.importOPML.title")
static let firstRunStepReviewTitle = String(localized: "firstRun.step.review.title")
static let firstRunStepDefaultsTitle = String(localized: "firstRun.step.defaults.title")
static let firstRunStepFinishTitle = String(localized: "firstRun.step.finish.title")
static let firstRunStepWelcomeLead = String(localized: "firstRun.step.welcome.lead")
static let firstRunStepAddFeedLead = String(localized: "firstRun.step.addFeed.lead")
static let firstRunStepImportOPMLLead = String(localized: "firstRun.step.importOPML.lead")
static let firstRunStepReviewLead = String(localized: "firstRun.step.review.lead")
static let firstRunStepDefaultsLead = String(localized: "firstRun.step.defaults.lead")
static let firstRunStepFinishLead = String(localized: "firstRun.step.finish.lead")
static let firstRunRailStartTitle = String(localized: "firstRun.rail.start.title")
static let firstRunRailStartSubtitle = String(localized: "firstRun.rail.start.subtitle")
static let firstRunRailFeedTitle = String(localized: "firstRun.rail.feed.title")
static let firstRunRailFeedSubtitle = String(localized: "firstRun.rail.feed.subtitle")
static let firstRunRailOPMLTitle = String(localized: "firstRun.rail.opml.title")
static let firstRunRailOPMLSubtitle = String(localized: "firstRun.rail.opml.subtitle")
static let firstRunRailReviewTitle = String(localized: "firstRun.rail.review.title")
static let firstRunRailReviewSubtitle = String(localized: "firstRun.rail.review.subtitle")
static let firstRunRailDefaultsTitle = String(localized: "firstRun.rail.defaults.title")
static let firstRunRailDefaultsSubtitle = String(localized: "firstRun.rail.defaults.subtitle")
static let firstRunRailFinishTitle = String(localized: "firstRun.rail.finish.title")
static let firstRunRailFinishSubtitle = String(localized: "firstRun.rail.finish.subtitle")
static let firstRunCardAddFeedTitle = String(localized: "firstRun.card.addFeed.title")
static let firstRunCardAddFeedSubtitle = String(localized: "firstRun.card.addFeed.subtitle")
static let firstRunCardImportOPMLTitle = String(localized: "firstRun.card.importOPML.title")
static let firstRunCardImportOPMLSubtitle = String(localized: "firstRun.card.importOPML.subtitle")
static let firstRunCardLaterTitle = String(localized: "firstRun.card.later.title")
static let firstRunCardLaterSubtitle = String(localized: "firstRun.card.later.subtitle")
static let firstRunFeedCheck = String(localized: "firstRun.feedCheck")
static let firstRunOtherOPML = String(localized: "firstRun.otherOPML")
static let firstRunDropHere = String(localized: "firstRun.dropHere")
static let firstRunDropHint = String(localized: "firstRun.dropHint")
static let firstRunDropOverlayTitle = String(localized: "firstRun.dropOverlay.title")
static let firstRunDropOverlayHint = String(localized: "firstRun.dropOverlay.hint")
static let firstRunSettingsMarkReadTitle = String(localized: "firstRun.settings.markRead.title")
static let firstRunSettingsMarkReadSubtitle = String(localized: "firstRun.settings.markRead.subtitle")
static let firstRunSettingsAutoRefreshTitle = String(localized: "firstRun.settings.autoRefresh.title")
static let firstRunSettingsAutoRefreshSubtitle = String(localized: "firstRun.settings.autoRefresh.subtitle")
static let firstRunSettingsIntervalTitle = String(localized: "firstRun.settings.interval.title")
static let firstRunSettingsIntervalSubtitle = String(localized: "firstRun.settings.interval.subtitle")
static let firstRunRefreshAfterTitle = String(localized: "firstRun.refreshAfter.title")
static let firstRunRefreshAfterSubtitle = String(localized: "firstRun.refreshAfter.subtitle")
static let firstRunStatusfilter = String(localized: "firstRun.statusfilter")
static let firstRunSelectAll = String(localized: "firstRun.selectAll")
static let firstRunDeselectAll = String(localized: "firstRun.deselectAll")
static let firstRunCreateFolder = String(localized: "firstRun.createFolder")
static let firstRunImportSummaryTitle = String(localized: "firstRun.importSummary.title")
static let firstRunImportSummaryDescription = String(localized: "firstRun.importSummary.description")
static let firstRunEditSelection = String(localized: "firstRun.editSelection")
static let firstRunMetricSelectedFeeds = String(localized: "firstRun.metric.selectedFeeds")
static let firstRunMetricFolders = String(localized: "firstRun.metric.folders")
static let firstRunMetricDuplicates = String(localized: "firstRun.metric.duplicates")
static let firstRunMetricUnreachable = String(localized: "firstRun.metric.unreachable")
static let firstRunFinishProblemsTitle = String(localized: "firstRun.finish.problems.title")
static let firstRunFinishOkTitle = String(localized: "firstRun.finish.ok.title")
static let firstRunFinishDescription = String(localized: "firstRun.finish.description")
static let firstRunMetricFeedsImported = String(localized: "firstRun.metric.feedsImported")
static let firstRunMetricFoldersUsed = String(localized: "firstRun.metric.foldersUsed")
static let firstRunMetricDuplicatesImported = String(localized: "firstRun.metric.duplicatesImported")
static let firstRunMetricUnreachableImported = String(localized: "firstRun.metric.unreachableImported")
static let firstRunHintsTitle = String(localized: "firstRun.hints.title")
static let firstRunNoImportTitle = String(localized: "firstRun.noImport.title")
static let firstRunNoImportSubtitle = String(localized: "firstRun.noImport.subtitle")
static let firstRunTableHeaderFeed = String(localized: "firstRun.tableHeader.feed")
static let firstRunTableHeaderFolder = String(localized: "firstRun.tableHeader.folder")
static let firstRunTableHeaderStatus = String(localized: "firstRun.tableHeader.status")
static let firstRunEmptyPreviewTitle = String(localized: "firstRun.emptyPreview.title")
static let firstRunEmptyPreviewSubtitle = String(localized: "firstRun.emptyPreview.subtitle")
static let firstRunEmptyFilterTitle = String(localized: "firstRun.emptyFilter.title")
static let firstRunEmptyFilterSubtitle = String(localized: "firstRun.emptyFilter.subtitle")
static let firstRunPreparingTitle = String(localized: "firstRun.preparing.title")
static let firstRunLater = String(localized: "firstRun.later")
static let firstRunBack = String(localized: "firstRun.back")
static let firstRunPrimaryWelcome = String(localized: "firstRun.primary.welcome")
static let firstRunPrimaryCheck = String(localized: "firstRun.primary.check")
static let firstRunPrimarySettings = String(localized: "firstRun.primary.settings")
static let firstRunPrimaryFinishShow = String(localized: "firstRun.primary.finishShow")
static let firstRunPrimaryImport = String(localized: "firstRun.primary.import")
static let firstRunPrimaryStart = String(localized: "firstRun.primary.start")
static let firstRunFeedAddressChecking = String(localized: "firstRun.feedAddress.checking")
static let firstRunFilterAll = String(localized: "firstRun.filter.all")
static let firstRunFilterNew = String(localized: "firstRun.filter.new")
static let firstRunFilterDuplicates = String(localized: "firstRun.filter.duplicates")
static let firstRunFilterUnreachable = String(localized: "firstRun.filter.unreachable")
static let firstRunProblemSkippedDuplicates = String(localized: "firstRun.problem.skippedDuplicates")
static let firstRunProblemNotRefreshed = String(localized: "firstRun.problem.notRefreshed")
```

- [ ] **Step 2: Plain-xcstrings-Tabelle**

`tools/first_run.tsv` (Ausschnitt der wesentlichen Werte; alle Keys oben müssen Zeilen haben — vollständige Tabelle durch den Implementer aus den Accessoren generieren, DE-Wert = aktueller Source-String):

```
key	de	en	fr	it
firstRun.titlebar.title	Feedivo einrichten	Set up Feedivo	Configurer Feedivo	Configura Feedivo
firstRun.step.welcome.title	Willkommen in Feedivo.	Welcome to Feedivo.	Bienvenue dans Feedivo.	Benvenuto in Feedivo.
firstRun.step.addFeed.title	Feed hinzufügen.	Add a feed.	Ajouter un flux.	Aggiungi un feed.
firstRun.step.importOPML.title	OPML importieren.	Import OPML.	Importer OPML.	Importa OPML.
firstRun.step.review.title	Auswahl prüfen.	Review selection.	Vérifier la sélection.	Verifica la selezione.
firstRun.step.defaults.title	Start-Einstellungen wählen.	Choose start settings.	Choisir les réglages de départ.	Scegli le impostazioni iniziali.
firstRun.step.finish.title	Feedivo ist bereit.	Feedivo is ready.	Feedivo est prêt.	Feedivo è pronto.
firstRun.step.welcome.lead	Wähle, wie du starten möchtest. Du kannst einen einzelnen Feed hinzufügen, viele Feeds aus einer OPML-Datei übernehmen oder Feedivo erst einmal leer öffnen.	Choose how to start. Add a single feed, import many feeds from an OPML file, or open Feedivo empty for now.	Choisissez comment démarrer. Ajoutez un flux, importez plusieurs flux depuis un fichier OPML, ou ouvrez Feedivo vide pour l'instant.	Scegli come iniziare. Aggiungi un feed, importa molti feed da un file OPML, oppure apri Feedivo vuoto per ora.
firstRun.step.addFeed.lead	Gib die Adresse eines RSS- oder Atom-Feeds ein. Feedivo prüft die Quelle, zeigt den Status und lässt dich direkt einen Ordner zuweisen.	Enter the address of an RSS or Atom feed. Feedivo checks the source, shows the status, and lets you assign a folder directly.	Saisissez l'adresse d'un flux RSS ou Atom. Feedivo vérifie la source, affiche le statut et vous permet d'attribuer un dossier directement.	Inserisci l'indirizzo di un feed RSS o Atom. Feedivo verifica la fonte, mostra lo stato e ti permette di assegnare una cartella direttamente.
firstRun.step.importOPML.lead	Lege eine OPML- oder XML-Datei ab oder wähle sie aus. Danach siehst du alle gefundenen Feeds, Ordner, Duplikate und nicht erreichbare Quellen, bevor etwas gespeichert wird.	Drop or select an OPML or XML file. You'll see all discovered feeds, folders, duplicates, and unreachable sources before anything is saved.	Déposez ou sélectionnez un fichier OPML ou XML. Vous verrez tous les flux trouvés, dossiers, doublons et sources inaccessibles avant tout enregistrement.	Trascina o seleziona un file OPML o XML. Vedrai tutti i feed trovati, le cartelle, i duplicati e le fonti non raggiungibili prima di salvare.
firstRun.step.review.lead	Kontrolliere die vorbereitete Auswahl. Die vollständige Feed-Liste kannst du bei Bedarf noch einmal öffnen und ändern.	Review the prepared selection. You can reopen and change the full feed list if needed.	Vérifiez la sélection préparée. Vous pouvez rouvrir et modifier la liste complète des flux si nécessaire.	Controlla la selezione preparata. Puoi riaprire e modificare la lista completa dei feed se necessario.
firstRun.step.defaults.lead	Lege die wichtigsten Startwerte fest. Diese Einstellungen kannst du später jederzeit in den Einstellungen ändern.	Set the most important start values. You can change these settings later anytime in Preferences.	Définissez les valeurs de départ les plus importantes. Vous pourrez modifier ces réglages plus tard dans les Préférences.	Imposta i valori iniziali più importanti. Potrai modificare queste impostazioni in seguito nelle Preferenze.
firstRun.step.finish.lead	Prüfe die Zusammenfassung des Imports. Feedivo öffnet sich erst, wenn du aktiv auf Starten klickst.	Review the import summary. Feedivo only opens once you click Start.	Vérifiez le résumé de l'import. Feedivo ne s'ouvre qu'une fois que vous cliquez sur Démarrer.	Verifica il riepilogo dell'import. Feedivo si apre solo quando clicchi Avvia.
firstRun.rail.start.title	Start	Start	Démarrer	Avvia
firstRun.rail.start.subtitle	Was möchtest du tun?	What do you want to do?	Que voulez-vous faire ?	Cosa vuoi fare?
firstRun.rail.feed.title	Feed	Feed	Flux	Feed
firstRun.rail.feed.subtitle	Adresse prüfen	Check address	Vérifier l'adresse	Verifica indirizzo
firstRun.rail.opml.title	OPML	OPML	OPML	OPML
firstRun.rail.opml.subtitle	Datei einlesen	Read file	Lire le fichier	Leggi file
firstRun.rail.review.title	Prüfen	Review	Vérifier	Verifica
firstRun.rail.review.subtitle	Auswahl bestätigen	Confirm selection	Confirmer la sélection	Conferma selezione
firstRun.rail.defaults.title	Einstellungen	Settings	Réglages	Impostazioni
firstRun.rail.defaults.subtitle	Lesen und Refresh	Read and refresh	Lecture et actualisation	Lettura e aggiornamento
firstRun.rail.finish.title	Fertig	Done	Terminé	Fatto
firstRun.rail.finish.subtitle	Direkt loslegen	Get started right away	Commencer directement	Inizia subito
firstRun.card.addFeed.title	Feed hinzufügen	Add a feed	Ajouter un flux	Aggiungi un feed
firstRun.card.addFeed.subtitle	Eine RSS-Adresse prüfen, optional einem Ordner zuweisen und importieren.	Check an RSS address, optionally assign a folder, and import.	Vérifier une adresse RSS, attribuer optionnellement un dossier, et importer.	Verifica un indirizzo RSS, assegna facoltativamente una cartella e importa.
firstRun.card.importOPML.title	OPML importieren	Import OPML	Importer OPML	Importa OPML
firstRun.card.importOPML.subtitle	Viele Feeds und vorhandene Ordner aus einem anderen RSS-Reader übernehmen.	Bring many feeds and existing folders from another RSS reader.	Reprendre plusieurs flux et dossiers existants d'un autre lecteur RSS.	Porta molti feed e cartelle esistenti da un altro lettore RSS.
firstRun.card.later.title	Später einrichten	Set up later	Configurer plus tard	Configura più tardi
firstRun.card.later.subtitle	Feedivo ohne Feeds öffnen. Du kannst später jederzeit neue Feeds hinzufügen.	Open Feedivo without feeds. You can add new feeds anytime later.	Ouvrir Feedivo sans flux. Vous pourrez ajouter des flux plus tard.	Apri Feedivo senza feed. Puoi aggiungere nuovi feed in qualsiasi momento.
firstRun.feedCheck	Feed prüfen	Check feed	Vérifier le flux	Verifica feed
firstRun.otherOPML	Andere OPML wählen	Choose other OPML	Choisir un autre OPML	Scegli altro OPML
firstRun.dropHere	OPML oder XML hier ablegen	Drop OPML or XML here	Déposer OPML ou XML ici	Trascina qui OPML o XML
firstRun.dropHint	oder Datei auswählen. Feedivo zeigt dir danach zuerst eine Vorschau.	or select a file. Feedivo shows a preview first.	ou sélectionner un fichier. Feedivo affiche d'abord un aperçu.	o seleziona un file. Feedivo mostra prima un'anteprima.
firstRun.dropOverlay.title	OPML-Datei hier ablegen	Drop OPML file here	Déposer le fichier OPML ici	Trascina qui il file OPML
firstRun.dropOverlay.hint	.opml und .xml werden unterstützt	.opml and .xml are supported	.opml et .xml sont pris en charge	.opml e .xml sono supportati
firstRun.settings.markRead.title	Artikel beim Öffnen als gelesen markieren	Mark articles read when opened	Marquer les articles comme lus à l'ouverture	Segna gli articoli come letti all'apertura
firstRun.settings.markRead.subtitle	Wenn du einen Artikel auswählst, verschwindet er automatisch aus Ungelesen.	When you select an article, it automatically leaves Unread.	Quando selezioni un articolo, lascia automatiquement Non lu.	Quando selezioni un articolo, lascia automaticamente Non letti.
firstRun.settings.autoRefresh.title	Automatisch aktualisieren	Refresh automatically	Actualiser automatiquement	Aggiorna automaticamente
firstRun.settings.autoRefresh.subtitle	Feedivo prüft deine Feeds regelmäßig, solange die App laufen darf.	Feedivo checks your feeds regularly while the app may run.	Feedivo vérifie régulièrement vos flux tant que l'app peut tourner.	Feedivo controlla regolarmente i feed finché l'app può girare.
firstRun.settings.interval.title	Refresh-Intervall	Refresh interval	Intervalle d'actualisation	Intervallo di aggiornamento
firstRun.settings.interval.subtitle	Gibt an, wie oft Feedivo nach neuen Artikeln suchen soll.	How often Feedivo should look for new articles.	À quelle fréquence Feedivo doit chercher de nouveaux articles.	Quanto spesso Feedivo deve cercare nuovi articoli.
firstRun.refreshAfter.title	Feeds nach Import direkt aktualisieren	Refresh feeds right after import	Actualiser les flux juste après l'import	Aggiorna i feed subito dopo l'import
firstRun.refreshAfter.subtitle	Lädt direkt Titel, Favicons und erste Artikel. Das dauert etwas länger.	Loads titles, favicons, and first articles directly. Takes a bit longer.	Charge titres, favicons et premiers articles directement. Prend un peu plus de temps.	Carica titoli, favicon e primi articoli direttamente. Richiede un po' più di tempo.
firstRun.statusfilter	Statusfilter	Status filter	Filtre de statut	Filtro di stato
firstRun.selectAll	Alle auswählen	Select all	Tout sélectionner	Seleziona tutti
firstRun.deselectAll	Alle abwählen	Deselect all	Tout désélectionner	Deseleziona tutti
firstRun.createFolder	Ordner erstellen	Create folder	Créer le dossier	Crea cartella
firstRun.importSummary.title	Import-Zusammenfassung	Import summary	Résumé de l'import	Riepilogo import
firstRun.importSummary.description	Diese Feeds werden gespeichert, wenn du fortfährst. Über „Auswahl bearbeiten“ kommst du zurück zur Liste.	These feeds are saved when you continue. Use “Edit selection” to return to the list.	Ces flux sont enregistrés si vous continuez. « Modifier la sélection » revient à la liste.	Questi feed vengono salvati quando prosegui. « Modifica selezione » torna alla lista.
firstRun.editSelection	Auswahl bearbeiten	Edit selection	Modifier la sélection	Modifica selezione
firstRun.metric.selectedFeeds	ausgewählte Feeds	selected feeds	flux sélectionnés	feed selezionati
firstRun.metric.folders	Ordner	Folders	Dossiers	Cartelle
firstRun.metric.duplicates	Duplikate erkannt	Duplicates detected	Doublons détectés	Duplicati rilevati
firstRun.metric.unreachable	nicht erreichbar	unreachable	inaccessibles	non raggiungibili
firstRun.finish.problems.title	Import abgeschlossen mit Hinweisen	Import complete with notes	Import terminé avec des remarques	Import completato con note
firstRun.finish.ok.title	Import abgeschlossen	Import complete	Import terminé	Import completato
firstRun.finish.description	Die ausgewählten Feeds wurden gespeichert. Hinweise zeigen dir, was noch Aufmerksamkeit braucht.	The selected feeds have been saved. Notes show what still needs attention.	Les flux sélectionnés ont été enregistrés. Les remarques indiquent ce qui requiert attention.	I feed selezionati sono stati salvati. Le note indicano cosa richiede attenzione.
firstRun.metric.feedsImported	Feeds importiert	Feeds imported	Flux importés	Feed importati
firstRun.metric.foldersUsed	Ordner angelegt/verwendet	Folders created/used	Dossiers créés/utilisés	Cartelle create/usate
firstRun.metric.duplicatesImported	Duplikate importiert	Duplicates imported	Doublons importés	Duplicati importati
firstRun.metric.unreachableImported	nicht erreichbare importiert	Unreachable imported	Inaccessibles importés	Non raggiungibili importati
firstRun.hints.title	Hinweise	Notes	Remarques	Note
firstRun.noImport.title	Noch kein Import gestartet.	No import started yet.	Aucun import démarré.	Nessun import avviato.
firstRun.noImport.subtitle	Gehe zurück und starte den Import oder öffne Feedivo ohne Feeds.	Go back and start the import or open Feedivo without feeds.	Revenez en arrière et lancez l'import ou ouvrez Feedivo sans flux.	Torna indietro e avvia l'import oppure apri Feedivo senza feed.
firstRun.tableHeader.feed	Feed	Feed	Flux	Feed
firstRun.tableHeader.folder	Ordner	Folder	Dossier	Cartella
firstRun.tableHeader.status	Status	Status	Statut	Stato
firstRun.emptyPreview.title	Noch keine Feeds geprüft.	No feeds checked yet.	Aucun flux vérifié.	Nessun feed verificato.
firstRun.emptyPreview.subtitle	Gib eine Feed-Adresse ein oder wähle eine OPML-Datei aus.	Enter a feed address or select an OPML file.	Saisissez une adresse de flux ou sélectionnez un fichier OPML.	Inserisci un indirizzo feed o seleziona un file OPML.
firstRun.emptyFilter.title	Keine Feeds für diesen Status.	No feeds for this status.	Aucun flux pour ce statut.	Nessun feed per questo stato.
firstRun.emptyFilter.subtitle	Wähle im Filter einen anderen Status, um weitere Feeds zu sehen.	Choose another status in the filter to see more feeds.	Choisissez un autre statut dans le filtre pour voir plus de flux.	Scegli un altro stato nel filtro per vedere più feed.
firstRun.preparing.title	Import-Vorschau wird vorbereitet	Preparing import preview	Préparation de l'aperçu d'import	Preparazione anteprima import
firstRun.later	Später	Later	Plus tard	Più tardi
firstRun.back	Zurück	Back	Retour	Indietro
firstRun.primary.welcome	Weiter	Next	Continuer	Avanti
firstRun.primary.check	Auswahl prüfen	Check selection	Vérifier la sélection	Verifica selezione
firstRun.primary.settings	Einstellungen wählen	Choose settings	Choisir les réglages	Scegli impostazioni
firstRun.primary.finishShow	Fertig anzeigen	Show summary	Afficher le résumé	Mostra riepilogo
firstRun.primary.import	Import starten	Start import	Lancer l'import	Avvia import
firstRun.primary.start	Starten	Start	Démarrer	Avvia
firstRun.feedAddress.checking	Feed-Adresse wird geprüft...	Checking feed address...	Vérification de l'adresse du flux...	Verifica indirizzo feed...
firstRun.filter.all	Alle	All	Tous	Tutti
firstRun.filter.new	Neu	New	Nouveau	Nuovo
firstRun.filter.duplicates	Duplikate	Duplicates	Doublons	Duplicati
firstRun.filter.unreachable	Nicht erreichbar	Unreachable	Inaccessibles	Non raggiungibili
firstRun.problem.skippedDuplicates	%lld doppelte Feeds wurden nicht importiert.	%lld duplicate feeds were not imported.	%lld flux en double n'ont pas été importés.	%lld feed duplicati non importati.
firstRun.problem.notRefreshed	Feeds wurden importiert, aber noch nicht aktualisiert.	Feeds were imported but not yet refreshed.	Les flux ont été importés mais pas encore actualisés.	I feed sono stati importati ma non ancora aggiornati.
```

(Hinweis: `firstRun.problem.skippedDuplicates` enthält `%lld` und wird unten als Plural-Eintrag nachgetragen; in der plain-Tabelle mit `state: translated` setzen ist zulässig, wird vom Plural-Inject überschrieben.)

- [ ] **Step 3: Plural-Tabelle FirstRun**

`tools/first_run_plural.tsv` (zusammengesetzte Zähl-Strings aus `selectedCountText`, `previewSummaryText`, `importSummaryText`, `intervalTitle`, `importButtonTitle`-Logik):

```
key	de_one	de_other	en_one	en_other	fr_one	fr_other	it_one	it_many
firstRun.selectedCount	Ausgewählt: %1$lld von %2$lld	Ausgewählt: %1$lld von %2$lld	Selected: %1$lld of %2$lld	Selected: %1$lld of %2$lld	Sélectionnés : %1$lld sur %2$lld	Sélectionnés : %1$lld sur %2$lld	Selezionati: %1$lld di %2$lld	Selezionati: %1$lld di %2$lld
firstRun.intervalMinutes	%lld Minute	%lld Minuten	%lld minute	%lld minutes	%lld minute	%lld minutes	%lld minuto	%lld minuti
firstRun.problem.skippedDuplicates	%lld doppelte Feed wurde nicht importiert.	%lld doppelte Feeds wurden nicht importiert.	%lld duplicate feed was not imported.	%lld duplicate feeds were not imported.	%lld flux en double n'a pas été importé.	%lld flux en double n'ont pas été importés.	%lld feed duplicato non importato.	%lld feed duplicati non importati.
```

(`previewSummaryText` ist ein zusammengesetzter Satz mit mehreren `%lld`; Pluralisierung mehrerer Counts in einem String ist nicht CLDR-tauglich. Daher wird `previewSummaryText` nicht pluralisiert, sondern als fester Plain-String mit festen deutschen Wörtern „Duplikate“/„nicht erreichbar“ je Sprache hinterlegt — bewusst akzeptiert laut Spec „FR/IT AI-Qualität ohne Native-Review“.)

```bash
python3 tools/l10n_inject.py --mode plain --table tools/first_run.tsv
python3 tools/l10n_inject.py --mode plural --table tools/first_run_plural.tsv
```

- [ ] **Step 4: View-Edits in FirstRunWizardView.swift**

`selectedCountText` (Zeile 39):

```swift
private var selectedCountText: String {
    String.localizedStringWithFormat(String(localized: "firstRun.selectedCount"),
                                     previewController.selectedImportRows.count,
                                     previewController.rows.count)
}
```

`stepTitle` (Zeile 189):

```swift
private var stepTitle: String {
    switch step {
    case .welcome: L10n.firstRunStepWelcomeTitle
    case .addFeed: L10n.firstRunStepAddFeedTitle
    case .importOPML: L10n.firstRunStepImportOPMLTitle
    case .review: L10n.firstRunStepReviewTitle
    case .defaults: L10n.firstRunStepDefaultsTitle
    case .finish: L10n.firstRunStepFinishTitle
    }
}
```

`stepLead` (Zeile 206): entsprechend auf `L10n.firstRunStepWelcomeLead` … `L10n.firstRunStepFinishLead` umstellen.

`stepItems` (Zeile 223): Titel/Subtitle auf `L10n.firstRunRail*Title`/`*Subtitle`.

`welcomeStep` (234): `FirstRunChoiceCard(... title: L10n.firstRunCardAddFeedTitle, subtitle: L10n.firstRunCardAddFeedSubtitle ...)` für alle drei Karten.

`addFeedStep` (270, 275): `Button(L10n.firstRunFeedCheck) { ... }`.

`opmlImportOptions` (321, 324): `Toggle(L10n.opmlImportAllowDuplicates, ...)` / `Toggle(L10n.opmlImportAllowUnreachable, ...)` (Keys aus Task 9).

`opmlSourceControl` (358): `Button(L10n.firstRunOtherOPML) { ... }`.

`opmlDropZone` (379, 381): `Text(L10n.firstRunDropHere)`, `Text(L10n.firstRunDropHint)`.

`defaultsStep` (399–418): `FirstRunSettingsLine(title: L10n.firstRunSettingsMarkReadTitle, subtitle: L10n.firstRunSettingsMarkReadSubtitle)` etc.

`refreshIntervalPicker` (444): `Picker(L10n.firstRunSettingsIntervalTitle, ...)`.

`reviewToolbar` (456, 475, 480, 485, 490): `Picker(L10n.firstRunStatusfilter, ...)`, `Button(L10n.firstRunSelectAll)`, `Button(L10n.firstRunDeselectAll)`, `TextField(L10n.opmlImportNewFolder, ...)`, `Button(L10n.firstRunCreateFolder)`.

`previewSummaryText` (498): ersetzen durch zusammengesetzten Plain-String mit `String(localized:)`-Bausteinen:

```swift
private var previewSummaryText: String {
    let rows = previewController.rows.count
    let dups = previewController.duplicateCount
    let unreach = previewController.unreachableCount
    let selected = previewController.selectedImportRows.count
    return "\(rows) \(L10n.opmlImportSummaryFeedsChecked) · \(dups) \(L10n.opmlImportSummaryDuplicates) · \(unreach) \(L10n.opmlImportSummaryUnreachable) · \(selected) \(L10n.opmlImportSummarySelected)"
}
```

(Diese `opmlImportSummary*`-Accessoren werden in Task 9 als Plain-Strings angelegt.)

`reviewSummaryCard` (512–533): `Text(L10n.firstRunImportSummaryTitle)`, `Text(L10n.firstRunImportSummaryDescription)`, `Button(L10n.firstRunEditSelection)`, Metric-Labels `L10n.firstRunMetricSelectedFeeds`/`Folders`/`Duplicates`/`Unreachable`.

`finishSummaryCard` (585–597): `Text(completionSummary.hasProblems ? L10n.firstRunFinishProblemsTitle : L10n.firstRunFinishOkTitle)`, `Text(L10n.firstRunFinishDescription)`, Metrics `firstRunMetricFeedsImported`/`FoldersUsed`/`DuplicatesImported`/`UnreachableImported`.

`finishSummaryCard`-Hinweise (602): `Text(L10n.firstRunHintsTitle)`.

`finishSummaryCard`-leer (629, 630): `centeredMessage(title: L10n.firstRunNoImportTitle, subtitle: L10n.firstRunNoImportSubtitle, ...)`.

`tableHeader` (706–710): `Text(L10n.firstRunTableHeaderFeed)`, `Text(L10n.firstRunTableHeaderFolder)`, `Text(L10n.firstRunTableHeaderStatus)`.

`feedTable`-leer (647, 648) / `emptyFilter` (652, 653): `centeredTableMessage(title: L10n.firstRunEmptyPreviewTitle, ...)` / `L10n.firstRunEmptyFilterTitle`.

`previewProgressRow` (687): `Text(L10n.firstRunPreparingTitle)`.

`optionToggles` (724): `FirstRunSettingsLine(title: L10n.firstRunRefreshAfterTitle, subtitle: L10n.firstRunRefreshAfterSubtitle)`.

`dropOverlay` (769, 771): `Text(L10n.firstRunDropOverlayTitle)`, `Text(L10n.firstRunDropOverlayHint)`.

`footer` (789, 796): `Button(L10n.firstRunLater)`, `Button(L10n.firstRunBack)`.

`primaryButtonTitle` (816–829): auf `L10n.firstRunPrimary*`-Accessoren umstellen; `case .defaults: previewController.selectedImportRows.isEmpty ? L10n.firstRunPrimaryFinishShow : L10n.firstRunPrimaryImport`; `case .finish: L10n.firstRunPrimaryStart`; `case .welcome: L10n.firstRunPrimaryWelcome`; `case .addFeed, .importOPML: L10n.firstRunPrimaryCheck`; `case .review: L10n.firstRunPrimarySettings`.

`importSummaryText` (848): wie `previewSummaryText` als zusammengesetzter Plain-String mit `L10n.opmlImportSummary*`-Bausteinen (gleiche Keys wie dort).

`intervalTitle` (852):

```swift
private func intervalTitle(_ interval: Int) -> String {
    String.localizedStringWithFormat(String(localized: "firstRun.intervalMinutes"), interval)
}
```

`filterButtonTitle` (856–866):

```swift
private func filterButtonTitle(_ filter: OPMLImportStatusFilter) -> String {
    switch filter {
    case .all: L10n.firstRunFilterAll
    case .available: L10n.firstRunFilterNew
    case .duplicates: L10n.firstRunFilterDuplicates
    case .unreachable: L10n.firstRunFilterUnreachable
    }
}
```

`prepareSingleFeedPreview` (953): `sourceText: L10n.firstRunFeedAddressChecking`.

`FirstRunCompletionSummary.problemMessages` (1079, 1083):

```swift
if skippedDuplicates > 0 {
    messages.append(String.localizedStringWithFormat(String(localized: "firstRun.problem.skippedDuplicates"), skippedDuplicates))
}
if !refreshAfterImport {
    messages.append(L10n.firstRunProblemNotRefreshed)
}
```

`titlebar` (111): `Text(L10n.firstRunTitlebarTitle)`.

- [ ] **Step 5: Build**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Views/FirstRun/FirstRunWizardView.swift \
  Feedivo/Resources/Localizable.xcstrings tools/first_run.tsv tools/first_run_plural.tsv
git commit -m "L10n Task 7: FirstRun-Cluster (Plain + View + Plural)"
```

---

### Task 8: Cluster OPMLImportReview (OPMLImportReviewView.swift)

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift`
- Create: `tools/opml_review.tsv`, `tools/opml_review_plural.tsv`

- [ ] **Step 1: L10n-Accessoren**

```swift
static let opmlImportTitle = String(localized: "opml.import.title")
static let opmlImportDescription = String(localized: "opml.import.description")
static let opmlImportStatusNoFile = String(localized: "opml.import.status.noFile")
static let opmlImportStatusReady = String(localized: "opml.import.status.ready")
static let opmlImportStatusDuplicateOne = String(localized: "opml.import.status.duplicate.one")
static let opmlImportStatusDuplicateMany = String(localized: "opml.import.status.duplicate.many")
static let opmlImportStatusUnreachable = String(localized: "opml.import.status.unreachable.count")
static let opmlImportChooseFile = String(localized: "opml.import.chooseFile")
static let opmlImportRemoveFile = String(localized: "opml.import.removeFile")
static let opmlImportStatusLabel = String(localized: "opml.import.statusLabel")
static let opmlImportTableHeaderFeed = String(localized: "opml.import.tableHeader.feed")
static let opmlImportTableHeaderWebsite = String(localized: "opml.import.tableHeader.website")
static let opmlImportTableHeaderFolder = String(localized: "opml.import.tableHeader.folder")
static let opmlImportTableHeaderStatus = String(localized: "opml.import.tableHeader.status")
static let opmlImportEmptyTitle = String(localized: "opml.import.empty.title")
static let opmlImportEmptySubtitle = String(localized: "opml.import.empty.subtitle")
static let opmlImportEmptyFilterTitle = String(localized: "opml.import.emptyFilter.title")
static let opmlImportEmptyFilterSubtitle = String(localized: "opml.import.emptyFilter.subtitle")
static let opmlImportPreparing = String(localized: "opml.import.preparing")
static let opmlImportRefreshAfter = String(localized: "opml.import.refreshAfter")
static let opmlImportAllowDuplicates = String(localized: "opml.import.allowDuplicates")
static let opmlImportAllowUnreachable = String(localized: "opml.import.allowUnreachable")
static let opmlImportCancel = String(localized: "opml.import.cancel")
static let opmlImportDropOverlayTitle = String(localized: "opml.import.dropOverlay.title")
static let opmlImportDropOverlayHint = String(localized: "opml.import.dropOverlay.hint")
static let opmlImportSelectionAll = String(localized: "opml.import.selection.all")
static let opmlImportSelectionVisible = String(localized: "opml.import.selection.visible")
static let opmlImportResultComplete = String(localized: "opml.import.result.complete")
static let opmlImportResultDuplicatesImported = String(localized: "opml.import.result.duplicatesImported")
static let opmlImportResultDuplicatesSkipped = String(localized: "opml.import.result.duplicatesSkipped")
static let opmlImportResultUnreachableImported = String(localized: "opml.import.result.unreachableImported")
static let opmlImportResultUnreachableSkipped = String(localized: "opml.import.result.unreachableSkipped")
static let opmlImportResultRefreshOn = String(localized: "opml.import.result.refreshOn")
static let opmlImportResultRefreshOff = String(localized: "opml.import.result.refreshOff")
static let opmlImportResultFoldersUsed = String(localized: "opml.import.result.foldersUsed")
```

(`opmlImportNewFolder`, `opmlImportCreateFolder`, `opmlImportSelectAll`, `opmlImportDeselectAll` werden in Task 9 zusammen mit den Controller-Strings angelegt.)

- [ ] **Step 2: Plain-xcstrings-Tabelle**

`tools/opml_review.tsv`:

```
key	de	en	fr	it
opml.import.title	Feeds aus OPML importieren	Import feeds from OPML	Importer des flux depuis OPML	Importa feed da OPML
opml.import.description	Prüfe die erkannten Feeds, passe Ordner an und entscheide, ob Feedivo direkt aktualisieren soll.	Review detected feeds, adjust folders, and decide whether Feedivo should refresh right away.	Vérifiez les flux détectés, ajustez les dossiers et décidez si Feedivo doit actualiser directement.	Verifica i feed trovati, regola le cartelle e decidi se Feedivo deve aggiornare subito.
opml.import.status.noFile	Keine Datei	No file	Aucun fichier	Nessun file
opml.import.status.ready	Bereit	Ready	Prêt	Pronto
opml.import.chooseFile	Datei auswählen...	Choose file...	Choisir le fichier...	Scegli file...
opml.import.removeFile	Entfernen	Remove	Supprimer	Rimuovi
opml.import.statusLabel	Status	Status	Statut	Stato
opml.import.tableHeader.feed	Feed	Feed	Flux	Feed
opml.import.tableHeader.website	Website	Website	Site Web	Sito web
opml.import.tableHeader.folder	Ordner	Folder	Dossier	Cartella
opml.import.tableHeader.status	Status	Status	Statut	Stato
opml.import.empty.title	Noch keine Datei ausgewählt.	No file selected yet.	Aucun fichier sélectionné.	Nessun file selezionato.
opml.import.empty.subtitle	Wähle eine OPML-Datei, danach erscheint hier die Import-Vorschau.	Choose an OPML file, then the import preview appears here.	Choisissez un fichier OPML, puis l'aperçu d'import apparaît ici.	Scegli un file OPML, poi l'anteprima di import apparirà qui.
opml.import.emptyFilter.title	Keine Feeds für diesen Status.	No feeds for this status.	Aucun flux pour ce statut.	Nessun feed per questo stato.
opml.import.emptyFilter.subtitle	Ändere den Statusfilter, um wieder mehr Feeds zu sehen.	Change the status filter to see more feeds.	Modifiez le filtre de statut pour voir plus de flux.	Cambia il filtro di stato per vedere più feed.
opml.import.preparing	Import-Vorschau wird vorbereitet	Preparing import preview	Préparation de l'aperçu d'import	Preparazione anteprima import
opml.import.refreshAfter	Feeds nach Import direkt aktualisieren	Refresh feeds right after import	Actualiser les flux juste après l'import	Aggiorna i feed subito dopo l'import
opml.import.allowDuplicates	Duplikate importieren	Import duplicates	Importer les doublons	Importa duplicati
opml.import.allowUnreachable	Nicht erreichbare Feeds importieren	Import unreachable feeds	Importer les flux inaccessibles	Importa feed non raggiungibili
opml.import.cancel	Abbrechen	Cancel	Annuler	Annulla
opml.import.dropOverlay.title	OPML-Datei hier ablegen	Drop OPML file here	Déposer le fichier OPML ici	Trascina qui il file OPML
opml.import.dropOverlay.hint	.opml und .xml werden unterstützt	.opml and .xml are supported	.opml et .xml sont pris en charge	.opml e .xml sono supportati
opml.import.selection.all	Ausgewählt: %1$lld von %2$lld	Selected: %1$lld of %2$lld	Sélectionnés : %1$lld sur %2$lld	Selezionati: %1$lld di %2$lld
opml.import.selection.visible	Ausgewählt: %1$lld von %2$lld sichtbar	Selected: %1$lld of %2$lld visible	Sélectionnés : %1$lld sur %2$lld visibles	Selezionati: %1$lld di %2$lld visibili
opml.import.result.complete	Import abgeschlossen	Import complete	Import terminé	Import completato
opml.import.result.duplicatesImported	%lld Duplikate bewusst importiert	%lld duplicates deliberately imported	%lld doublons importés délibérément	%lld duplicati importati deliberatamente
opml.import.result.duplicatesSkipped	%lld Duplikate angezeigt und übersprungen	%lld duplicates shown and skipped	%lld doublons affichés et ignorés	%lld duplicati mostrati e saltati
opml.import.result.unreachableImported	%lld nicht erreichbare Feeds bewusst importiert	%lld unreachable feeds deliberately imported	%lld flux inaccessibles importés délibérément	%lld feed non raggiungibili importati deliberatamente
opml.import.result.unreachableSkipped	%lld nicht erreichbare Feeds angezeigt und übersprungen	%lld unreachable feeds shown and skipped	%lld flux inaccessibles affichés et ignorés	%lld feed non raggiungibili mostrati e saltati
opml.import.result.refreshOn	Direktes Aktualisieren ist aktiv.	Direct refresh is on.	L'actualisation directe est activée.	L'aggiornamento diretto è attivo.
opml.import.result.refreshOff	Aktualisierung erfolgt später manuell.	Refresh happens later manually.	L'actualisation se fera plus tard manuellement.	L'aggiornamento avverrà più tardi manualmente.
opml.import.result.foldersUsed	Ordner verwendet	Folders used	Dossiers utilisés	Cartelle usate
```

- [ ] **Step 3: Plural-Tabelle (statusText + importButtonTitle)**

`tools/opml_review_plural.tsv`:

```
key	de_one	de_other	en_one	en_other	fr_one	fr_other	it_one	it_many
opml.import.status.duplicate	%lld Duplikat	%lld Duplikate	%lld duplicate	%lld duplicates	%lld doublon	%lld doublons	%lld duplicato	%lld duplicati
opml.import.status.unreachable	%lld nicht erreichbar	%lld nicht erreichbar	%lld unreachable	%lld unreachable	%lld inaccessible	%lld inaccessibles	%lld non raggiungibile	%lld non raggiungibili
opml.import.button.import	%lld Feed importieren	%lld Feeds importieren	Import %lld feed	Import %lld feeds	Importer %lld flux	Importer %lld flux	Importa %lld feed	Importa %lld feed
```

```bash
python3 tools/l10n_inject.py --mode plain --table tools/opml_review.tsv
python3 tools/l10n_inject.py --mode plural --table tools/opml_review_plural.tsv
```

- [ ] **Step 4: View-Edits in OPMLImportReviewView.swift**

```swift
// Zeile 61/63: Header
Text(L10n.opmlImportTitle)
Text(L10n.opmlImportDescription)

// Zeile 118-131: statusText
private var statusText: String {
    if previewController.rows.isEmpty {
        return L10n.opmlImportStatusNoFile
    }
    var parts: [String] = []
    if previewController.duplicateCount > 0 {
        parts.append(String.localizedStringWithFormat(String(localized: "opml.import.status.duplicate"), previewController.duplicateCount))
    }
    if previewController.unreachableCount > 0 {
        parts.append(String.localizedStringWithFormat(String(localized: "opml.import.status.unreachable"), previewController.unreachableCount))
    }
    return parts.isEmpty ? L10n.opmlImportStatusReady : parts.joined(separator: " · ")
}

// Zeile 172/174: dropOverlay
Text(L10n.opmlImportDropOverlayTitle)
Text(L10n.opmlImportDropOverlayHint)

// Zeile 186/210/216: filePicker
Text("OPML")  // Marken-Kürzel, unlokalisiert
Button(L10n.opmlImportChooseFile) { ... }
Button(L10n.opmlImportRemoveFile) { ... }

// Zeile 260: statusFilter-Picker
Picker(L10n.opmlImportStatusLabel, selection: $previewController.statusFilter) {
    ForEach(OPMLImportStatusFilter.allCases) { filter in
        Text(filter.localizedTitle).tag(filter)  // localizedTitle aus Task 9
    }
}

// Zeile 269/275/284/288: toolbar-Buttons
Button(L10n.opmlImportSelectAll) { ... }
Button(L10n.opmlImportDeselectAll) { ... }
TextField(L10n.opmlImportNewFolder, text: $previewController.newFolderName)
Button(L10n.opmlImportCreateFolder) { ... }

// Zeile 337-343: tableHeader
Text(L10n.opmlImportTableHeaderFeed).frame(maxWidth: .infinity, alignment: .leading)
Text(L10n.opmlImportTableHeaderWebsite).frame(width: 180, alignment: .leading)
Text(L10n.opmlImportTableHeaderFolder).frame(width: 154, alignment: .leading)
Text(L10n.opmlImportTableHeaderStatus).frame(width: 108, alignment: .leading)

// Zeile 356/357, 363/364: emptyRow / emptyFilterRow
centeredTableMessage(title: L10n.opmlImportEmptyTitle, subtitle: L10n.opmlImportEmptySubtitle)
centeredTableMessage(title: L10n.opmlImportEmptyFilterTitle, subtitle: L10n.opmlImportEmptyFilterSubtitle)

// Zeile 373: previewProgressRow
Text(L10n.opmlImportPreparing)

// Zeile 406-410: footer toggles
Toggle(L10n.opmlImportRefreshAfter, isOn: $previewController.refreshAfterImport)
Toggle(L10n.opmlImportAllowDuplicates, isOn: $previewController.allowsDuplicates)
Toggle(L10n.opmlImportAllowUnreachable, isOn: $previewController.allowsUnreachable)

// Zeile 415: Abbrechen
Button(L10n.opmlImportCancel) { dismiss() }

// Zeile 429-431: importButtonTitle
private var importButtonTitle: String {
    String.localizedStringWithFormat(String(localized: "opml.import.button.import"),
                                     previewController.selectedImportRows.count)
}

// Zeile 435-440: selectionSummaryText
private var selectionSummaryText: String {
    if previewController.statusFilter == .all {
        return String.localizedStringWithFormat(String(localized: "opml.import.selection.all"),
                                                previewController.selectedImportRows.count,
                                                previewController.rows.count)
    }
    return String.localizedStringWithFormat(String(localized: "opml.import.selection.visible"),
                                             previewController.selectedImportRows.count,
                                             previewController.visibleRowCount)
}

// Zeile 467-474: importSelectedFeeds resultMessage
let duplicateText = importedDuplicateCount > 0
    ? String.localizedStringWithFormat(String(localized: "opml.import.result.duplicatesImported"), importedDuplicateCount)
    : String.localizedStringWithFormat(String(localized: "opml.import.result.duplicatesSkipped"), previewController.duplicateCount)
let unreachableText = importedUnreachableCount > 0
    ? String.localizedStringWithFormat(String(localized: "opml.import.result.unreachableImported"), importedUnreachableCount)
    : String.localizedStringWithFormat(String(localized: "opml.import.result.unreachableSkipped"), previewController.unreachableCount)
let foldersText = String.localizedStringWithFormat(String(localized: "opml.import.result.foldersUsed"), previewController.folderCount)
let refreshText = previewController.refreshAfterImport ? L10n.opmlImportResultRefreshOn : L10n.opmlImportResultRefreshOff
previewController.resultMessage = "\(L10n.opmlImportResultComplete): \(result.imported) \(… importedCount-Baustein …), \(duplicateText), \(unreachableText), \(foldersText). \(refreshText)"
```

(`result.imported` ist eine nicht-pluralisierte nackte Zahl im zusammengesetzten Satz; der Implementer nutzt `String.localizedStringWithFormat(String(localized: "opml.export.feedCount"), result.imported)` als Baustein — dieser Key existiert bereits mit Plural-Varianten aus Task 2.)

- [ ] **Step 5: Build**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Views/OPMLImport/OPMLImportReviewView.swift \
  Feedivo/Resources/Localizable.xcstrings tools/opml_review.tsv tools/opml_review_plural.tsv
git commit -m "L10n Task 8: OPMLImportReview-Cluster (Plain + View + Plural)"
```

---

### Task 9: Cluster OPMLImportPreviewController (Plain-Strings) + shared OPML/FirstRun-Toggles

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift`
- Modify: `Feedivo/Tests/OPMLImportPreviewControllerTests.swift` (Sentinel-Behauptung dokumentieren)
- Create: `tools/opml_controller.tsv`

**Interfaces:**
- Produces: `OPMLImportStatusFilter.localizedTitle: String`, `OPMLImportPreviewConfiguration` mit lokalisierten Initial-Strings, Controller-Plain-Strings via `String(localized:)`.
- Bewusst nicht lokalisiert: Sentinel `"Ohne Ordner"` (Datenlogik in `folderCount`, Spec observation 1060) — bleibt als interner Schlüssel.

- [ ] **Step 1: L10n-Accessoren**

```swift
static let opmlImportFilterAll = String(localized: "opml.import.filter.all")
static let opmlImportFilterAvailable = String(localized: "opml.import.filter.available")
static let opmlImportFilterDuplicates = String(localized: "opml.import.filter.duplicates")
static let opmlImportFilterUnreachable = String(localized: "opml.import.filter.unreachable")
static let opmlImportSheetSourceDescription = String(localized: "opml.import.sheet.sourceDescription")
static let opmlImportSheetProgressEmpty = String(localized: "opml.import.sheet.progressEmpty")
static let opmlImportSheetNoFileName = String(localized: "opml.import.sheet.noFileName")
static let opmlImportFirstRunSourceDescription = String(localized: "opml.import.firstRun.sourceDescription")
static let opmlImportFirstRunProgressEmpty = String(localized: "opml.import.firstRun.progressEmpty")
static let opmlImportProgressReadingFile = String(localized: "opml.import.progress.readingFile")
static let opmlImportProgressPreparing = String(localized: "opml.import.progress.preparing")
static let opmlImportProgressFeedsRecognized = String(localized: "opml.import.progress.feedsRecognized")
static let opmlImportProgressCheckStart = String(localized: "opml.import.progress.checkStart")
static let opmlImportProgressCheckDone = String(localized: "opml.import.progress.checkDone")
static let opmlImportProgressFeedsChecked = String(localized: "opml.import.progress.feedsChecked")
static let opmlImportErrorUnreadable = String(localized: "opml.import.error.unreadable")
static let opmlImportErrorDropFormat = String(localized: "opml.import.error.dropFormat")
static let opmlImportSummaryFeedsChecked = String(localized: "opml.import.summary.feedsChecked")
static let opmlImportSummaryDuplicates = String(localized: "opml.import.summary.duplicates")
static let opmlImportSummaryUnreachable = String(localized: "opml.import.summary.unreachable")
static let opmlImportSummarySelected = String(localized: "opml.import.summary.selected")
static let opmlImportNewFolder = String(localized: "opml.import.newFolder")
static let opmlImportCreateFolder = String(localized: "opml.import.createFolder")
static let opmlImportSelectAll = String(localized: "opml.import.selectAll")
static let opmlImportDeselectAll = String(localized: "opml.import.deselectAll")
```

- [ ] **Step 2: xcstrings-Tabelle**

`tools/opml_controller.tsv`:

```
key	de	en	fr	it
opml.import.filter.all	Alle Stati	All statuses	Tous les statuts	Tutti gli stati
opml.import.filter.available	Neue Feeds	New feeds	Nouveaux flux	Nuovi feed
opml.import.filter.duplicates	Duplikate	Duplicates	Doublons	Duplicati
opml.import.filter.unreachable	Nicht erreichbar	Unreachable	Inaccessibles	Non raggiungibili
opml.import.sheet.sourceDescription	Wähle eine .opml- oder .xml-Datei, danach erscheint hier die Import-Vorschau.	Choose a .opml or .xml file, then the import preview appears here.	Choisissez un fichier .opml ou .xml, puis l'aperçu d'import apparaît ici.	Scegli un file .opml o .xml, poi l'anteprima di import apparirà qui.
opml.import.sheet.progressEmpty	Noch keine Datei ausgewählt.	No file selected yet.	Aucun fichier sélectionné.	Nessun file selezionato.
opml.import.sheet.noFileName	Keine OPML-Datei ausgewählt	No OPML file selected	Aucun fichier OPML sélectionné	Nessun file OPML selezionato
opml.import.firstRun.sourceDescription	Wähle aus, wie du deine ersten Feeds hinzufügen möchtest.	Choose how to add your first feeds.	Choisissez comment ajouter vos premiers flux.	Scegli come aggiungere i tuoi primi feed.
opml.import.firstRun.progressEmpty	Noch keine Feeds geprüft.	No feeds checked yet.	Aucun flux vérifié.	Nessun feed verificato.
opml.import.progress.readingFile	Datei wird gelesen...	Reading file...	Lecture du fichier...	Lettura del file...
opml.import.progress.preparing	OPML-Datei wird gelesen und vorbereitet.	Reading and preparing OPML file.	Lecture et préparation du fichier OPML.	Lettura e preparazione del file OPML.
opml.import.progress.feedsRecognized	%lld Feeds erkannt. Feed-Adressen werden geprüft...	%lld feeds found. Checking feed addresses...	%lld flux trouvés. Vérification des adresses...	%lld feed trovati. Verifica degli indirizzi...
opml.import.progress.checkStart	%lld Feeds erkannt. Prüfung startet...	%lld feeds found. Check starting...	%lld flux trouvés. Vérification en cours...	%lld feed trovati. Verifica in corso...
opml.import.progress.checkDone	Prüfung abgeschlossen.	Check complete.	Vérification terminée.	Verifica completata.
opml.import.progress.feedsChecked	%lld Feeds geprüft.	%lld feeds checked.	%lld flux vérifiés.	%lld feed verificati.
opml.import.error.unreadable	Die Datei konnte nicht gelesen werden.	The file could not be read.	Le fichier n'a pas pu être lu.	Il file non può essere letto.
opml.import.error.dropFormat	Bitte eine OPML- oder XML-Datei ablegen.	Please drop an OPML or XML file.	Veuillez déposer un fichier OPML ou XML.	Trascina un file OPML o XML.
opml.import.summary.feedsChecked	Feeds geprüft	feeds checked	flux vérifiés	feed verificati
opml.import.summary.duplicates	Duplikate	duplicates	doublons	duplicati
opml.import.summary.unreachable	nicht erreichbar	unreachable	inaccessibles	non raggiungibili
opml.import.summary.selected	ausgewählt	selected	sélectionnés	selezionati
opml.import.newFolder	Neuer Ordner	New folder	Nouveau dossier	Nuova cartella
opml.import.createFolder	Ordner erstellen	Create folder	Créer le dossier	Crea cartella
opml.import.selectAll	Alle auswählen	Select all	Tout sélectionner	Seleziona tutti
opml.import.deselectAll	Alle abwählen	Deselect all	Tout désélectionner	Deseleziona tutti
```

Plural für `feedsRecognized` / `checkStart` / `feedsChecked` (alle `%lld`-Zähl-Strings im Controller):

`tools/opml_controller_plural.tsv`:

```
key	de_one	de_other	en_one	en_other	fr_one	fr_other	it_one	it_many
opml.import.progress.feedsRecognized	%lld Feed erkannt. Feed-Adressen werden geprüft...	%lld Feeds erkannt. Feed-Adressen werden geprüft...	%lld feed found. Checking feed addresses...	%lld feeds found. Checking feed addresses...	%lld flux trouvé. Vérification des adresses...	%lld flux trouvés. Vérification des adresses...	%lld feed trovato. Verifica degli indirizzi...	%lld feed trovati. Verifica degli indirizzi...
opml.import.progress.checkStart	%lld Feed erkannt. Prüfung startet...	%lld Feeds erkannt. Prüfung startet...	%lld feed found. Check starting...	%lld feeds found. Check starting...	%lld flux trouvé. Vérification en cours...	%lld flux trouvés. Vérification en cours...	%lld feed trovato. Verifica in corso...	%lld feed trovati. Verifica in corso...
opml.import.progress.feedsChecked	%lld Feed geprüft.	%lld Feeds geprüft.	%lld feed checked.	%lld feeds checked.	%lld flux vérifié.	%lld flux vérifiés.	%lld feed verificato.	%lld feed verificati.
```

```bash
python3 tools/l10n_inject.py --mode plain --table tools/opml_controller.tsv
python3 tools/l10n_inject.py --mode plural --table tools/opml_controller_plural.tsv
```

- [ ] **Step 3: Controller-Edits in OPMLImportPreviewController.swift**

`OPMLImportStatusFilter.title` ersetzen durch `localizedTitle`:

```swift
var localizedTitle: String {
    switch self {
    case .all: L10n.opmlImportFilterAll
    case .available: L10n.opmlImportFilterAvailable
    case .duplicates: L10n.opmlImportFilterDuplicates
    case .unreachable: L10n.opmlImportFilterUnreachable
    }
}
```

(Den alten `title`-Computed-Property entfernen; Aufrufer in OPMLImportReviewView nutzen ab Task 8 `filter.localizedTitle`. Bestehende Tests, die `.title` asserten, in Step 5 anpassen.)

`OPMLImportPreviewConfiguration`-Static-Initialisierungen (Zeile 75–87):

```swift
static let importSheet = OPMLImportPreviewConfiguration(
    initialSourceDescription: L10n.opmlImportSheetSourceDescription,
    initialPreviewProgressText: L10n.opmlImportSheetProgressEmpty,
    initialSelectedFileName: L10n.opmlImportSheetNoFileName
)

static let firstRun = OPMLImportPreviewConfiguration(
    initialSourceDescription: L10n.opmlImportFirstRunSourceDescription,
    initialPreviewProgressText: L10n.opmlImportFirstRunProgressEmpty,
    initialSelectedFileName: L10n.opmlImportSheetNoFileName
)
```

In `loadOPML` (Zeile 270–312) alle Plain-String-Zuweisungen ersetzen:

```swift
selectedFileName = url.lastPathComponent
sourceDescription = L10n.opmlImportProgressReadingFile
previewProgressText = L10n.opmlImportProgressPreparing
…
sourceDescription = String.localizedStringWithFormat(String(localized: "opml.import.progress.feedsRecognized"), opmlFeeds.count)
previewProgressText = String.localizedStringWithFormat(String(localized: "opml.import.progress.checkStart"), opmlFeeds.count)
…
// Zeile 298: zusammengesetzter Satz — Sentinel „Ohne Ordner" bleibt intern
let folderCount = Set(rows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count
sourceDescription = "\(String.localizedStringWithFormat(String(localized: "opml.import.progress.feedsRecognized").components(separatedBy: ".").first ?? "", rows.count)) \(…)"
```

(Einfacher und deterministisch: `sourceDescription` für die fertige Zeile 298 als eigenen Plain-Key `opml.import.progress.recognizedWithFolders` anlegen. Das vermeidet String-Zerlegung. — Stattdessen in der Tabelle ergänzen:)

Ergänze in `tools/opml_controller.tsv` zusätzlich:

```
opml.import.progress.recognizedWithFolders	%1$lld Feeds erkannt · %2$lld Ordner · %3$@	%1$lld feeds found · %2$lld folders · %3$@	%1$lld flux trouvés · %2$lld dossiers · %3$@	%1$lld feed trovati · %2$lld cartelle · %3$@
```

(Re-Inject nach Ergänzung; idempotent.) Und in `loadOPML`:

```swift
let folderCount = Set(rows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count
sourceDescription = String.localizedStringWithFormat(
    String(localized: "opml.import.progress.recognizedWithFolders"),
    rows.count, folderCount, url.lastPathComponent)
previewProgressText = L10n.opmlImportProgressCheckDone
```

`preparePreview` (Zeile 345–346):

```swift
sourceDescription = String.localizedStringWithFormat(String(localized: "opml.import.progress.feedsChecked"), rows.count)
previewProgressText = L10n.opmlImportProgressCheckDone
```

Fehler-Pfade (310/311, 376):

```swift
errorMessage = error.localizedDescription
sourceDescription = L10n.opmlImportErrorUnreadable
previewProgressText = L10n.opmlImportErrorUnreadable
…
self.errorMessage = L10n.opmlImportErrorDropFormat
```

- [ ] **Step 4: FirstRun-`opmlImportOptions`-Toggles**

Die `opmlImportOptions`-Toggles in `FirstRunWizardView` (Zeile 321/324) referenzieren `L10n.opmlImportAllowDuplicates`/`L10n.opmlImportAllowUnreachable` (Task 7 setzt voraus, dass diese hier angelegt sind — Reihenfolge: Task 9 vor Task 7 ausführen ODER die Strings in Task 7 inline als `String(localized: "opml.import.allowDuplicates")` nutzen). Konsens: Task 9 zuerst mergen, dann Task 7.

- [ ] **Step 5: Tests anpassen**

In `FeedivoTests/OPMLImportPreviewControllerTests.swift`: alle Assertions auf `OPMLImportStatusFilter.title` durch `localizedTitle` ersetzen; bei Assertions gegen deutsche Titel-Werte prüfen, ob sie auf `localizedTitle` im DE-Source-Locale laufen (Source-Sprache ist DE → identisch). Zusätzlich Kommentar ergänzen, dass `"Ohne Ordner"` bewusst Sentinel bleibt (nicht lokalisiert).

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/OPMLImportPreviewControllerTests test 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 6: Build + Tests**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5
xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test -only-testing:FeedivoTests 2>&1 | tail -15
```
Expected: BUILD SUCCEEDED; FeedivoTests PASS.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift \
  FeedivoTests/OPMLImportPreviewControllerTests.swift Feedivo/Resources/Localizable.xcstrings \
  tools/opml_controller.tsv tools/opml_controller_plural.tsv
git commit -m "L10n Task 9: OPMLImportPreviewController-Plain-Strings (+ shared Toggles)"
```

---

### Task 10: Verifikation

**Files:** — keine weiteren Edits; ggf. `docs/superpowers/l10n/inventar.md` nachführen.

- [ ] **Step 1: Vollständiger Build + Tests**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5
xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test -only-testing:FeedivoTests 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED; alle FeedivoTests-Suiten grün.

- [ ] **Step 2: Katalog-Vollständigkeit prüfen (kein EN-Fehlbestand)**

```bash
python3 - <<'PY'
import json
d=json.load(open('Feedivo/Resources/Localizable.xcstrings',encoding='utf-8'))['strings']
missing=[]
for k,v in d.items():
    locs=v.get('localizations',{})
    for lang in ['en','fr','it']:
        u=locs.get(lang,{}).get('stringUnit') or (locs.get(lang,{}).get('variations',{}).get('plural',{}).get('one') or {}).get('stringUnit')
        if not u or u.get('state')!='translated':
            missing.append((k,lang))
print('fehlende Übersetzungen:', len(missing))
for m in missing[:20]: print(' -',m)
PY
```
Expected: `fehlende Übersetzungen: 0` (oder nur bewusst nicht-lokalisierte Keys auflisten).

- [ ] **Step 3: Manuelle Sprachumschaltung (Stichprobe)**

```bash
xcodebuild -scheme Feedivo -destination 'platform=macOS' -launchArgument '-AppleLanguages (en)' build 2>&1 | tail -3
# dann App manuell starten: xcodebuild ... oder Xcode Scheme-Argument setzen.
```
Stichproben: Default-Ordner-Namen in Sidebar englisch; „1 min read" vs. „5 mins read" im Reader; FirstRun „Welcome to Feedivo."; OPML-Status „1 duplicate" / „3 duplicates".

- [ ] **Step 4: Inventar nachführen + Commit**

```bash
git add docs/superpowers/l10n/inventar.md
git commit -m "L10n Task 10: Inventar finalisiert, Verifikation grün"
```

- [ ] **Step 5: Branch-Finalisierung (Optional, nach Nutzer-Review)**

Per `superpowers:finishing-a-development-branch`: PR gegen `main` öffnen, Code-Review anfordern.

---

## Self-Review

**1. Spec coverage:**
- Abschnitt 1 (Inventur, Task 0) → Task 0 + `inventar.md`. ✓
- Abschnitt 2 (24 Plural-Strings) → Task 2 (23 TSV-Keys + SmartFolderEditor-Plural in Task 5 = 24). ✓
- Abschnitt 3 (`defaultKey`-Modell, Anzeige, Restore, Migration, Editor-Sperre, Test) → Task 1 Steps 3–8 + Test. ✓
- Abschnitt 4 (`L10n.swift`-Accessor plain/view, xcstrings-Einträge 4 Sprachen, Batching je Cluster, TDD) → `l10n_inject.py` + Tasks 3–9, TDD in Task 1. ✓
- Abschnitt 5 (Build + FeedivoTests, manuelle Sprachumschaltung, kein pbxproj, dt. Kommentare, Verhaltenserhalt) → Task 10 + Global Constraints. ✓
- Global Constraints (CloudKit-safe defaultKey, dt. Kommentare, kein pbxproj, Verhaltenserhalt) → Task 1 + Global Constraints. ✓

**2. Placeholder scan:** Keine „TODO/TBD"-Marker. FirstRun-`previewSummaryText`/`importSummaryText` nutzen konkret benannte `L10n.opmlImportSummary*`-Accessoren (Task 9). `resultMessage`-Baustein nutzt existierenden `opml.export.feedCount`-Plural-Key. Einzelfälle: FirstRun-Tabelle ist groß; der Implementer muss die TSV-Zeilen aus den Accessoren vollständig erzeugen — die DE-Werte stehen im Plan (Source-Strings aus der View), EN/FR/IT für alle Keys in der Tabelle gelistet.

**3. Type consistency:**
- `SmartFolder.defaultKey: String?` konsistent in Modell, `defaultFolders`, `restoreDefaultFolders`, `foldersSortedWithDefaultsFirst`, Migration, Editor. ✓
- `localizedDisplayName: String` in `SmartFolder` genutzt von Sidebar/Settings/Editor. ✓
- `OPMLImportStatusFilter.localizedTitle: String` (neu) ersetzt `title` (entfernt); Aufrufer in OPMLImportReviewView + Tests angepasst. ✓
- `L10n`-Accessoren: `LocalizedStringKey` für View-`Text`/`Button`/`Toggle`/`Picker`; `String(localized:)` für Plain-String-Kontexte (FirstRun, OPML-Controller, statusText, resultMessage). Trennung konsequent. ✓
- `l10n_inject.py`-Spaltennamen `de_one`/`de_other`/`it_many` stimmen mit `PLURAL_CATS`. ✓
- Reihenfolge-Abhängigkeit: Task 9 (shared Toggles/Filter) muss vor Task 7/8 liegen, da diese `L10n.opmlImportAllowDuplicates`/`localizedTitle` konsumieren. Im Plan in Task 1 Step 8 und Task 7/8 entsprechend vermerkt; empfohlene Ausführungsreihenfolge: 0 → 1 → 9 → 2 → 3 → 4 → 5 → 6 → 8 → 7 → 10. ✓ (in Handoff erwähnen)

**Hinweis zu Ausführungsreihenfolge:** Tasks 7 und 8 konsumieren Accessoren aus Task 9 (`opmlImportAllow*`, `opmlImportSelectAll/DeselectAll/NewFolder/CreateFolder`, `OPMLImportStatusFilter.localizedTitle`). Task 9 ist deshalb vor 7/8 auszuführen. Task 1 Step 8 (Editor-Name-Sperre) konsumiert `smartFolderFieldName`/`smartFolderShowInSidebar` aus Task 5 — daher Task 5 vor Task 1 Step 8, oder Task 1 ohne Step 8 committen und Step 8 mit Task 5 zusammenführen. Empfohlen: Task 1 (ohne Editor-Step 8) → Task 9 → Task 5 (inkl. Editor-Step 8-Umstellung) → …