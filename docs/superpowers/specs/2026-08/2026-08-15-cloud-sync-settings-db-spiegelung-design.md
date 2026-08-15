# Design: iCloud-Sync-Aktiv-Flag über die Datenbank statt UserDefaults spiegeln

**Datum:** 2026-08-15
**Status:** Zur Review

## Kontext

Im finalen Whole-Branch-Review des MCP-Server V2 Phase 1 (Schreibzugriff-Fundament,
siehe `docs/superpowers/specs/2026-08/2026-08-14-mcp-server-v2-phase1-schreibzugriff-design.md`)
wurde ein Important-Fund gemacht: MCP-Server-Schreibvorgänge (`update_article_status`,
`assign_tag`, `remove_tag`) erreichen **nie** iCloud Sync.

**Root Cause:** `CloudSyncSettings.isEnabled(in: UserDefaults = .standard)` liest
`UserDefaults.standard`. Der `FeedivoMCPServer`-Prozess ist bewusst **unsandboxed**
(siehe ADR-011) — sein `UserDefaults.standard` zeigt auf eine andere Preferences-Domäne
als die der sandboxed Feedivo-App. Dadurch liefert `isEnabled()` im MCP-Prozess praktisch
immer `false`, unabhängig vom tatsächlichen Nutzer-Setting.

**Konsequenz:** Store-Methoden wie `ArticleStatusStore.updateBooleanStatus` setzen bei
jedem Schreibvorgang trotzdem `statusSyncUpdatedAt = Date()` — die Zeile *sieht* für den
Sync-Layer frisch geändert aus, aber `enqueuePendingSync` (gated hinter
`CloudSyncSettings.isEnabled()`) reiht nichts ein. Ergebnis: Der Wert wird nie zu anderen
Geräten gepusht, UND `CloudSyncArticleStatusMapping`s Last-Write-Wins-Vergleich hält die
Zeile für "neuer als jede eingehende Remote-Änderung" — ein von einem anderen Gerät
kommender Wert wird dadurch dauerhaft unterdrückt. Zwei über iCloud Sync verbundene Geräte
können so nach einer MCP-Schreibaktion permanent auseinanderlaufen.

Betroffen sind **7 Stellen**, die alle über dieselbe Funktion gaten:
`TagStore.swift:21`, `FeedFolderStore.swift:33,42`, `ArticleStatusStore.swift:142`,
`SQLiteRuleStore.swift:15`, `FeedStore.swift:16`, `SQLiteSmartFolderStore.swift:16`,
`CloudSyncArticleStatusMapping.swift:186`. Aktuell sind nur `TagStore`/`ArticleStatusStore`
über MCP-Schreib-Tools erreichbar — Phase 2 (Feed hinzufügen/entfernen) würde aber auch
`FeedStore`/`FeedFolderStore` treffen. Der Fix behebt deshalb alle 7 Stellen einheitlich,
nicht nur die aktuell betroffenen zwei.

## Architektur

**Migration v33** legt eine neue Single-Row-Tabelle `cloud_sync_settings` an
(`id INTEGER PRIMARY KEY`, `isEnabled INTEGER NOT NULL DEFAULT 0`), analog zu
`mcp_server_settings` (v31). Beim Anlegen wird die Zeile **nicht** einfach mit `0`
initialisiert, sondern mit dem aktuellen `UserDefaults.standard`-Wert von
`CloudSyncSettings.isEnabledKey` befüllt (derselbe Lookup wie `CloudSyncSettings.
isEnabled(in:)` selbst: `object(forKey:) != nil ? bool(forKey:) : defaultIsEnabled`) —
ein Bestandsnutzer, der iCloud Sync bereits aktiviert hat, wird beim Update nicht
stillschweigend auf "aus" zurückgesetzt.

**Neuer Store `CloudSyncSettingsStore`** (`Feedivo/Stores/CloudSyncSettingsStore.swift`),
strukturell identisch zu `MCPServerSettingsStore`:
```swift
func isEnabled() throws -> Bool   // fail-closed: false bei jedem Fehler
func setEnabled(_ isEnabled: Bool) throws
```

**`CloudSyncSettings` (Enum) bleibt unverändert.** Sie bleibt die alleinige Quelle für
UI-Zwecke (`@AppStorage`-Bindung des Schalters in `SyncSettingsView`,
`statusLocalizationKey`, `FeedivoApp.swift`s `CloudSyncEngine`-Konstruktion beim
App-Start) — all das läuft ausschließlich im App-Prozess, UserDefaults ist dafür
weiterhin korrekt und schneller/reaktiver als ein DB-Read.

**Die 7 Store-seitigen Gates** wechseln von `CloudSyncSettings.isEnabled()` auf
`CloudSyncSettingsStore(database: self.database).isEnabled()` — jede dieser Methoden
läuft bereits innerhalb eines Store mit `database`-Zugriff, die Umstellung ist an jeder
Stelle rein mechanisch (kein neuer Parameter nötig, `self.database` ist bereits vorhanden).

## Datenfluss

1. Nutzer schaltet "iCloud Sync" in den Einstellungen um → `@AppStorage`
   (`cloudSyncIsEnabled`) aktualisiert sich sofort, UI-Verhalten unverändert.
2. Der bereits bestehende `.onChange(of: cloudSyncIsEnabled)`-Handler in
   `SyncSettingsView` (`SettingsView.swift:1286-1306`) bekommt eine zusätzliche Zeile:
   `try? CloudSyncSettingsStore(database: feedivoDatabase).setEnabled(cloudSyncIsEnabled)`
   — spiegelt den neuen Wert in die DB, im selben Atemzug wie die bestehende
   Erst-Aktivierungs-/Stop-Logik.
3. Jede Store-Mutation — unabhängig davon, ob sie aus der App oder aus dem
   `FeedivoMCPServer`-Prozess kommt — liest `CloudSyncSettingsStore(...).isEnabled()` und
   reiht bei `true` korrekt in die Pending-Sync-Warteschlange ein.

## Fehlerbehandlung

`CloudSyncSettingsStore.isEnabled()` ist fail-closed: jeder DB-Fehler (fehlende Tabelle,
Lesefehler) liefert `false` — ein Store-Gate, das im Zweifel NICHT synct, ist sicherer als
eines, das im Zweifel synct (kein Datenverlust, nur ein potenziell verzögerter Push, der
sich beim nächsten erfolgreichen Read von selbst löst).

## Testing

- Migration v33: neuer Test mirrort das v31/v32-Muster — Tabelle existiert, Backfill
  respektiert einen vorab in `UserDefaults.standard` gesetzten Wert (Test setzt/räumt
  `UserDefaults.standard` explizit auf, mit `defer`-Cleanup, analog zum bereits
  etablierten Muster in den 17 unten genannten Testdateien).
- `CloudSyncSettingsStore`: neue Testsuite, identisch zu `MCPServerSettingsStoreTests`
  (Standardwert, Persistenz, Fail-Closed-Verhalten bei fehlender Tabelle).
- **17 bestehende Testdateien**, die aktuell `UserDefaults.standard.set(true, forKey:
  CloudSyncSettings.isEnabledKey)` nutzen, um "Sync aktiv" für Store-Tests zu simulieren,
  müssen auf `CloudSyncSettingsStore(database:).setEnabled(true)` umgestellt werden —
  gruppiert nach betroffenem Store, damit Produktionscode-Änderung und ihre Tests im
  selben Task landen:
  - `TagStore.swift` → `SQLiteTagStoreTests.swift`, `TagStoreChangedFieldsTests.swift`
  - `FeedFolderStore.swift` (2 Stellen) → `FeedFolderStoreTests.swift`,
    `FeedFolderStoreChangedFieldsTests.swift`
  - `ArticleStatusStore.swift` → `SQLiteArticleStatusStoreTests.swift` (+ ggf.
    `SQLiteFeedArticleListStateTests.swift`, `ArticleRetentionCleanupServiceTests.swift`,
    je nach tatsächlicher Abhängigkeit — im Plan verifizieren)
  - `SQLiteRuleStore.swift` → `SQLiteRuleStoreTests.swift`,
    `SQLiteRuleStoreChangedFieldsTests.swift`
  - `FeedStore.swift` → `SQLiteFeedStoreTests.swift`, `FeedStoreChangedFieldsTests.swift`
  - `SQLiteSmartFolderStore.swift` → `SQLiteSmartFolderStoreTests.swift`,
    `SQLiteSmartFolderStoreChangedFieldsTests.swift`
  - `CloudSyncArticleStatusMapping.swift` → `CloudSyncArticleStatusMappingTests.swift`
  - `CloudSyncSettingsTests.swift`, `CloudSyncEngineFieldConflictTests.swift`,
    `CloudSyncEngineResetTests.swift`, `FeedivoAppSceneConfigurationTests.swift`: im Plan
    einzeln prüfen, ob sie tatsächlich einen der 7 Store-Gates berühren oder nur
    `CloudSyncSettings` selbst (bleibt unverändert) bzw. den `isEnabledKey`-Namen als
    String referenzieren — nicht blind mitändern.
- Nach der Umstellung: gezielter Regressionslauf über alle 17 (+2 neue) betroffenen
  Suiten, sowie Debug- und Release-Build.

## Out of Scope

- Keine Änderung an `CloudSyncSettings` selbst oder an der UI-Bindung des Schalters.
- Keine Änderung an `pendingFirstActivationKey` oder der Erst-Aktivierungs-Logik.
- Keine rückwirkende Reparatur bereits divergierter Geräte (kein automatischer
  Re-Sync-Trigger) — Nutzer, die bereits vom beschriebenen Bug betroffen waren, müssten
  bei Bedarf manuell über die bestehende Soft-/Hard-Reset-UI neu synchronisieren.
