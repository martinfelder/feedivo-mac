# Design: Offline-Artikel-Download-Feature vollständig entfernen

**Datum:** 2026-07-20
**Status:** Zur Umsetzung freigegeben

## Kontext

Das Offline-Artikel-Download-Feature (Backend: `SQLiteOfflineStore`,
`SQLiteOfflineDownloadService`, `OfflineArticleContentFetching`-Protokoll) hat seit dem
Dead-Code-Cleanup vom 2026-07-10 keine aktive UI-Anbindung mehr — es war seither bewusst
quarantäniert (siehe CLAUDE.md-Gotcha „Offline-Artikel-Download-Backend ist bewusst
quarantäniert") mit der offenen Entscheidung „reaktivieren oder endgültig entfernen".
Diese Session trifft die Entscheidung: **endgültig entfernen.**

Eine Recherche vor diesem Design deckte auf, dass die Entfernung größer ist als die
ursprüngliche Gotcha-Notiz „Backend + Tests + L10n-Keys" nahelegt: Die Felder
`offlineState`/`offlineContent` sind über `LEFT JOIN article_offline` fest in die
produktiven Artikel-Ladepfade verdrahtet (`ArticleListSQL.swift`, `ArticleStore.swift`)
und werden vom aktiv genutzten Artikel-Export-Feature verwendet (bevorzugt beim Export
vorhandenen Offline-Volltext gegenüber dem Feed-Inhalt). Diese Kopplung wird als Teil
dieser Entfernung mit aufgelöst — sonst bliebe nach der Backend-Löschung dauerhaft toter
Code im aktiven Export-Pfad zurück (die Tabelle wäre für immer leer, die
„Offline bevorzugen"-Logik würde nie mehr greifen).

## Ziel

Alle Code-, Datenbank- und Dokumentationsspuren des Offline-Download-Features werden aus
`main` entfernt. Das Artikel-Export-Feature funktioniert danach unverändert, nur ohne die
(ohnehin nie erreichbare) Offline-Bevorzugung — es exportiert ausschließlich den
Feed-Inhalt.

**Nicht Teil dieser Änderung:**
- Die Git-Worktrees/Branches `codex/sqlite-grdb-foundation` und `codex/icloud-sync-beta`
  (eigenständige, teils pausierte Entwicklungsstränge mit eigener Historie — Nutzerentscheid,
  um spätere Merge-/Rebase-Konflikte zu vermeiden)
- `networkStatusOffline` (Netzwerkstatus-Anzeige) und die "Bilder offline im Export
  verfügbar machen"-Strings (`articleExportOfflineImagesToggle` u. a.) — eigenständige,
  aktive Features, die zufällig ähnliche Namen tragen
- `docs/archive/FEATURES-legacy-2026-06-24.md` — historisches Archiv-Dokument, bewusst
  nicht nachträglich umgeschrieben

## Umfang

### 1. Vollständig zu löschende Dateien

- `Feedivo/Stores/SQLiteOfflineStore.swift`
- `Feedivo/Services/OfflineArticleContentFetching.swift`
- `Feedivo/Database/Records/ArticleOfflineRecord.swift`
- `FeedivoTests/SQLiteOfflineDownloadServiceTests.swift`

### 2. Zu modifizierende Dateien (Entkopplung)

- `Feedivo/Snapshots/ArticleListSnapshot.swift` — `offlineStateRaw`/`offlineState` entfernen
- `Feedivo/Snapshots/ArticleReaderSnapshot.swift` — `offlineStateRaw`, `offlineContent`,
  `offlineRequestedAt`, `offlineSavedAt`, `offlineErrorMessage`, `offlineState` entfernen
- `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift` — `offlineState` entfernen
- `Feedivo/Stores/ArticleListSQL.swift` — `LEFT JOIN article_offline`/
  `COALESCE(o.state, 'none') AS offlineStateRaw` aus dem gemeinsamen SQL-Fragment entfernen
- `Feedivo/Stores/ArticleStore.swift` — zwei weitere `LEFT JOIN article_offline`-Stellen
  entfernen (u. a. in `readerArticle(id:)`)
- `Feedivo/Services/ArticleExportService.swift` + `Feedivo/Services/
  ArticleDocumentExportRenderers.swift` — `preferredContent(for:)` vereinfacht auf
  ausschließlich Feed-Inhalt, keine Offline-Alternative mehr
- `Feedivo/Views/ArticleList/ArticleExportSheet.swift` — Anzeige der Offline-Quelle
  (`L10n.articleExportSourceOffline`-Verwendung an dieser Stelle) entfernt

### 3. Datenbank-Migration

Neue Migration `v17_drop_article_offline_table` (die bestehende
`v5_create_article_offline_table` bleibt unverändert — keine nachträgliche Änderung
alter Migrationen):

```swift
migrator.registerMigration("v17_drop_article_offline_table") { db in
    try db.drop(index: "idx_article_offline_state")
    try db.drop(table: "article_offline")
}
```

### 4. L10n

23 eindeutig zugehörige, bereits unbenutzte `L10n.swift`-Konstanten entfernen:
`readerOfflineSave`, `readerOfflineRemove`, `readerOfflineSaving`,
`readerOfflineFullTextAvailable`, `readerOfflineFeedContentAvailable`,
`readerOfflineFailed`, `readerOfflineNotSaved`, `readerInspectorOfflineAndContentSection`,
`readerInspectorOfflineStatus`, `readerInspectorOfflineDetail`, `settingsOfflineSection`,
`settingsOfflineDescription`, `settingsOfflineManualTitle`,
`settingsOfflineManualDescription`, `settingsOfflineFeedContentTitle`,
`settingsOfflineFeedContentDescription`, `settingsOfflineAutomationTitle`,
`settingsOfflineAutomationDescription`, `settingsOfflineAutoSaveStarredTitle`,
`settingsOfflineAutoSaveStarredDescription`, `articleRowOfflineAvailable`,
`articleRowOfflineFailed`, `offlineArchiveErrorTitle`, `offlineArchiveErrorMessage` —
plus die zugehörigen `Localizable.xcstrings`-Einträge (Text-Anker-Entfernung, kein
`json.load`/`json.dump`-Roundtrip, siehe bekannter Formatierungs-Gotcha) und die 3
direkten `String(localized:)`-Keys aus der gelöschten `OfflineArticleContentFetching.swift`
(`offline.error.missingOriginalURL`, `offline.error.emptyDownloadedContent`,
`offline.error.unreachable`).

**Nicht entfernen:** `networkStatusOffline`, `articleExportOfflineImagesToggle*`,
`articleExportSourceOffline` (Achtung: `articleExportSourceOffline` selbst bleibt als
Konstante bestehen, nur ihre Verwendungsstelle in `ArticleExportSheet.swift` entfällt —
falls sie dadurch zu einem unbenutzten Key wird, ist das separat zu prüfen, nicht
Teil dieser Aufräumaktion).

### 5. Tests

- **Löschen:** `FeedivoTests/SQLiteOfflineDownloadServiceTests.swift` (komplette Datei)
- **Löschen (Einzeltests):** `FeedivoTests/FeedivoAppSceneConfigurationTests.swift:234-253`
  (`offlineArtikelKopienSindNichtMehrImProduktivenUIPfadVerdrahtet()`) und die
  Einzel-Assertion zu Zeile 784 (veralteter Klassenname `OfflineDownloadService`) — beide
  Regressionstests werden durch die vollständige Löschung selbst obsolet (sie prüfen die
  Abwesenheit von Symbolen, die es nach dieser Änderung ohnehin nicht mehr gibt)
- **Invertieren:** `FeedivoTests/SQLiteDatabaseMigrationTests.swift` — Prüfungen auf
  Existenz von `article_offline`/`idx_article_offline_state` (Zeilen 20, 50) werden zu
  Prüfungen auf **Nicht-Existenz** nach der neuen Migration; Migrationsnamen-Liste
  (Zeile 449) bekommt `v17_drop_article_offline_table` ergänzt
- **Anpassen:** `FeedivoTests/ArticleExportServiceTests.swift` (Zeilen 27-34, 499-519) —
  Fixture-Daten verlieren die `ArticleOfflineState`/`offlineStateRaw`/`offlineContent`-Felder,
  Tests prüfen den Export-Inhalt danach nur noch gegen reinen Feed-Inhalt

### 6. Dokumentation

- `CLAUDE.md`: Gotcha-Eintrag „Offline-Artikel-Download-Backend ist bewusst
  quarantäniert" wird durch eine Erledigt-Notiz unter „Letzte Änderungen" ersetzt; der
  Eintrag unter „Offene Entscheidungen" entfällt (Entscheidung getroffen); betroffene
  Verzeichnisbaum-Referenzen bereinigt

## Testing

- `xcodebuild build` muss nach jeder Task grün sein
- Gezielte Tests: `SQLiteDatabaseMigrationTests` (invertierte Assertions +
  neuer Migrationsname), `ArticleExportServiceTests` (angepasste Fixtures),
  `FeedivoAppSceneConfigurationTests` (nach Löschung der zwei Offline-Assertions
  weiterhin grün)
- Keine neuen Tests nötig — dies ist eine reine Entfernung, kein neues Verhalten

## Manuelle Live-Verifikationscheckliste (für den Implementierungsplan vorzusehen)

1. App-Start auf einer bestehenden Datenbank mit älterem Schema — Migration
   `v17_drop_article_offline_table` läuft fehlerfrei durch (kein Crash, kein
   Datenverlust bei anderen Tabellen)
2. Artikel exportieren (Markdown/PDF/DOCX) — Inhalt entspricht weiterhin dem
   Feed-Inhalt, keine Regression im Export-Dialog
3. Artikelliste/Reader laden weiterhin normal (keine SQL-Fehler durch entfernten JOIN)
