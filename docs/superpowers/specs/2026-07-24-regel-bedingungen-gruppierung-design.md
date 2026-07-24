# Design-Spec: Freie Gruppierung von Regel-Bedingungen (UND/ODER)

**Datum:** 2026-07-24
**Status:** Vom Nutzer freigegeben, bereit für Implementierungsplan

## Ausgangslage

Im Power-User-Modus des Regel-Assistenten (`RuleWizardView.swift`) lassen sich mehrere
Bedingungen hinzufügen. Aktuell gibt es dafür nur einen globalen Umschalter
„Treffer bei: Alle Bedingungen / Eine reicht" (`RuleMatchMode.all`/`.any`), der
einheitlich auf **alle** Bedingungen einer Regel angewendet wird — echtes Mischen von
UND und ODER (z. B. „Bedingung 1 UND Bedingung 2, ODER Bedingung 3") ist damit nicht
möglich.

**Nutzerwunsch:** Bedingungen sollen sich frei in Gruppen einteilen lassen. Eine Ebene
Verschachtelung reicht aus (keine Gruppen-in-Gruppen): mehrere Gruppen, jede Gruppe
intern UND-verknüpft, die Gruppen selbst ODER-verknüpft — z. B.
`(A UND B) ODER (C UND D) ODER E`.

## Entscheidungen aus dem Brainstorming

- **Verschachtelungstiefe:** Eine Ebene reicht (keine Gruppen in Gruppen).
- **Bedienkonzept:** Variante B — explizite, umrandete Gruppen-Boxen (nicht implizite
  Verbinder-Toggles zwischen einzelnen Bedingungen, obwohl mathematisch äquivalent —
  der Nutzer bevorzugt die expliziten Boxen als klarere Bedienung).
- **Bedingungen bleiben in ihrer Gruppe:** Kein nachträgliches Verschieben einer
  Bedingung zwischen Gruppen nötig (weder Dropdown noch Drag & Drop) — Bedingungen
  werden direkt in der Box angelegt, in der sie bleiben sollen.

## 1. Datenmodell & Migration

`RuleConditionRecord` (Tabelle `rule_conditions`) bekommt ein neues Feld
`groupIndex: Int` (Default `0`). Bedingungen mit demselben `groupIndex` innerhalb
derselben Regel sind UND-verknüpft; unterschiedliche `groupIndex`-Werte werden
ODER-verknüpft.

Neue additive Migration `v20_add_rule_condition_group_index` — letzte bestehende
Migration zum Zeitpunkt dieser Spec ist `v19_drop_article_offline_table`
(verifiziert per `grep -n registerMigration` in `FeedivoDatabaseMigrator.swift`,
**vor Implementierung erneut prüfen**, siehe CLAUDE.md-Gotcha zu Migrationsnummern).

`RuleConditionDraft` (das Wizard-interne Bearbeitungsmodell in
`Feedivo/Models/RuleConditionDraft.swift`) bekommt dasselbe Feld `groupIndex: Int`.

**Bestandsregeln-Migration (Backfill):** Die neue Migration befüllt `groupIndex` für
alle existierenden Zeilen in `rule_conditions` anhand des bisherigen
`rules.matchMode` der zugehörigen Regel:
- `matchMode == "all"`: alle Bedingungen der Regel bekommen `groupIndex = 0` (eine
  einzige Gruppe — entspricht exakt dem bisherigen UND-Verhalten).
- `matchMode == "any"`: jede Bedingung bekommt einen eigenen, fortlaufenden
  `groupIndex` (0, 1, 2, …) in ihrer bisherigen `sortOrder`-Reihenfolge — entspricht
  exakt dem bisherigen ODER-Verhalten (jede Bedingung ist für sich allein
  ausreichend).

Die alte Spalte `rules.matchMode` bleibt in der Datenbank bestehen (Migrationen
löschen nie rückwirkend Spalten), wird aber ab dieser Änderung von der
Auswertungslogik nicht mehr gelesen — sie ist danach vestigial. Ein Entfernen der
Spalte selbst ist **nicht** Teil dieser Spec (eigener, späterer Cleanup-Schritt,
analog zum bisherigen Projektmuster bei anderen ausgemusterten Spalten).

## 2. Auswertungslogik (`RuleEngine.swift`)

Die private Funktion `matches(conditions:matchMode:article:)` (aktuell:
`.allSatisfy`/`.contains` je nach `matchMode`) wird ersetzt durch eine
gruppenbasierte Auswertung:

```
func matches(conditions: [NormalizedCondition], article: ArticleRuleSnapshot) -> Bool {
    let groups = Dictionary(grouping: conditions, by: \.groupIndex)
    guard !groups.isEmpty else { return false }  // unveraendert: keine Bedingungen -> kein Match
    return groups.values.contains { group in
        group.allSatisfy { condition in matches(condition: condition, article: article) }
    }
}
```

`matchMode: RuleMatchMode` entfällt als Parameter dieser Funktion und aus dem
Aufrufpfad in `RuleEngine.swift` vollständig (die Datenstruktur `NormalizedCondition`
bekommt stattdessen ein `groupIndex`-Feld). `RuleMatchMode` selbst (der Typ) bleibt
vorerst im Code bestehen, falls er an anderer Stelle (Smart Folders,
`SmartFolderEditorView.swift`/`SmartFolderFormatter.swift`) weiterhin unabhängig
genutzt wird — **muss vor Planbeginn verifiziert werden**, ob Smart Folders einen
eigenen, von dieser Änderung unabhängigen Anwendungsfall für `RuleMatchMode` haben
(erste Einschätzung: ja, Smart Folders sind ein separates Feature mit eigener
Bedingungs-Logik, von dieser Spec nicht betroffen — nur die *Regeln*-Auswertung in
`RuleEngine.swift` ändert sich).

## 3. UI im Regel-Assistenten (Power-User-Modus, `RuleWizardView.swift`)

Der bisherige globale „Treffer bei: Alle Bedingungen / Eine reicht"-Umschalter
(`RuleSegmentedControl` mit `RuleMatchMode.allCases`, aktuell Zeilen 218–231) entfällt
vollständig. Stattdessen:

- Bedingungen werden nach `groupIndex` gruppiert dargestellt. Jede Gruppe ist eine
  umrandete Box (neue Komponente, angelehnt an bestehende `RuleDialogTheme`-Kartenoptik)
  mit ihren UND-verknüpften `RuleConditionRow`-Zeilen (bestehende Komponente,
  unverändert wiederverwendet).
- Zwischen zwei Gruppen-Boxen steht ein zentrierter „ODER"-Trenner (Pill-Badge im
  Stil des bestehenden `RuleDialogBadge`).
- Jede Box hat unten einen „+ Bedingung"-Button (bestehender Stil: gestrichelter
  Rahmen, wie der aktuelle globale „+ Bedingung hinzufügen"-Button) — fügt eine
  weitere Bedingung **innerhalb dieser Box** hinzu (automatisch UND-verknüpft mit den
  anderen Bedingungen der Box, kein Verbinder-UI nötig).
- Unter der letzten Box: ein „+ ODER-Gruppe hinzufügen"-Button — legt eine neue,
  leere Box mit einer einzelnen Startbedingung an.
- Jede Box hat einen Löschen-Button, der die komplette Gruppe samt aller ihrer
  Bedingungen entfernt — ausgeblendet, wenn es die einzige verbleibende Box ist.
- Wird die letzte Bedingung einer Box einzeln über das bestehende Lösch-Icon einer
  `RuleConditionRow` entfernt, wird die dadurch leere Box automatisch mitentfernt
  (kein Zustand mit einer leeren Box möglich).
- Es bleibt immer mindestens eine Box mit mindestens einer Bedingung bestehen (analog
  zur heutigen Regel, dass die letzte Bedingung nicht entfernbar ist —
  `showRemove: mode == .power && conditionDrafts.count > 1` wird zu einer
  gruppenbewussten Variante).
- Der Simple-Modus (`mode == .simple`, nur eine Bedingung, kein Hinzufügen-Button)
  bleibt vollständig unverändert — dort existierte ohnehin nie mehr als eine Gruppe
  mit einer Bedingung.

## 4. Zusammenfassungstext in der Regel-Liste (`RuleSettingsFormatter.conditionSummary`)

Aktuell: alle Bedingungsbeschreibungen werden mit einem einzigen, aus `matchMode`
abgeleiteten Konnektor (` UND ` bzw. ` ODER `) verbunden.

Neu: Bedingungen werden nach `groupIndex` gruppiert (Reihenfolge der Gruppen nach dem
kleinsten `sortOrder` ihrer Bedingungen). Innerhalb einer Gruppe werden die
Beschreibungen mit ` UND ` verbunden. Gibt es mehr als eine Gruppe, wird jede
Mehr-Bedingungs-Gruppe in Klammern gesetzt, und die Gruppen werden mit ` ODER `
verbunden — z. B. `(Titel enthält X UND Feed ist Y) ODER Autor ist Z`. Eine Gruppe
mit nur einer Bedingung bekommt keine Klammern (unnötiges visuelles Rauschen). Bei
nur einer Gruppe insgesamt bleiben alle Klammern weg (identisch zum heutigen
Verhalten für reine UND-Regeln).

## 5. Testing

Neue/angepasste Tests:
- `RuleEngineTests` (oder passende bestehende Testdatei): gruppenbasierte Auswertung
  — eine Gruppe (bisheriges UND-Verhalten unverändert), mehrere Gruppen mit
  gemischten Treffern/Nicht-Treffern (mind. ein Fall, wo Gruppe 1 nicht, Gruppe 2
  aber matcht → Gesamtergebnis Treffer), keine Bedingungen (weiterhin kein Match).
- Migrationstest (`SQLiteDatabaseMigrationTests.swift`, Muster wie bei v19): Backfill
  für `matchMode == "all"` → eine Gruppe; `matchMode == "any"` → N Einzelgruppen in
  `sortOrder`-Reihenfolge.
- `RuleSettingsFormatter`-Tests: Klammerung bei mehreren Gruppen, keine Klammern bei
  einer Gruppe oder Einzel-Bedingungs-Gruppen.
- Wizard-UI-Zustandslogik (falls testbar ohne Live-Rendering, sonst als manueller
  Prüfpunkt dokumentieren): Gruppe hinzufügen, Gruppe explizit löschen, letzte
  Bedingung einer Gruppe entfernen → Gruppe verschwindet automatisch, immer
  mindestens eine Bedingung insgesamt bleibt erhalten.

## Offene technische Prüfpunkte für die Implementierungsplanung

- Exakter aktueller Stand von `FeedivoDatabaseMigrator.swift` (letzte Migration)
  erneut per Grep verifizieren, nicht diese Spec als Quelle nehmen (Migrationsnummer
  könnte sich bis zur Implementierung verschoben haben).
- Verifizieren, ob `RuleMatchMode` (der Typ) noch von Smart-Folder-Code
  (`SmartFolderEditorView.swift`, `SmartFolderFormatter.swift`,
  `SQLiteSmartFolderStore.swift`, `SmartFolderRecord.swift`) unabhängig von Regeln
  genutzt wird — falls ja, bleibt der Typ vollständig unangetastet, nur sein Einsatz
  in `RuleEngine.swift`/`RuleWizardView.swift`/`RuleSettingsView.swift` entfällt.
- Exakte Benennung der neuen Gruppen-Box-Komponente und Einordnung in bestehende
  `RuleDialogTheme`-Stildatei vs. neue eigene Datei — Implementierungsdetail für den
  Plan, nicht für diese Spec.
