# M3 Rule Wizard Design

## Ziel

M3 Block D erweitert die vorhandene RuleEngine zu einer nutzbaren Regelverwaltung.
Nutzer sollen Regeln nicht als technische Liste pflegen muessen, sondern ueber einen
Wizard erstellen und bearbeiten koennen. Gleichzeitig sollen alle Regeln zentral in
den Einstellungen sichtbar sein.

## Produktentscheidung

Regeln bekommen zwei Einstiegsmodi:

- Einfach: gefuehrter Wizard fuer eine einzelne Bedingung.
- Power User: Wizard fuer mehrere Bedingungen mit `AND` oder `OR`.

Die Power-User-Variante ist der bevorzugte Modus fuer Nutzer, die genau steuern
moechten, wann ein Tag automatisch vergeben wird. Regex, verschachtelte
Bedingungsgruppen und Aktionen ausser `Tag zuweisen` bleiben spaetere Ausbaustufen.

## Umfang

Enthalten in diesem Block:

- Datenmodell-Erweiterung fuer mehrere Bedingungen pro Regel.
- Migration der bisherigen einfachen `Rule`-Felder in neue `RuleCondition`-Objekte.
- RuleEngine wertet mehrere Bedingungen mit `AND` oder `OR` aus.
- Wizard zum Erstellen und Bearbeiten von Regeln.
- Settings-Bereich mit Liste aller Regeln.
- Aktiv/Inaktiv-Toggle, Bearbeiten und Loeschen in den Einstellungen.
- Sidebar zeigt Regeln nur kompakt an und bietet einen Einstieg, um aus dem aktuell
  ausgewaehlten Artikel eine neue Regel vorzubereiten.

Nicht enthalten in diesem Block:

- Regex.
- Verschachtelte Gruppen wie `(A AND B) OR C`.
- Rueckwirkendes Anwenden auf vorhandene Artikel.
- Feed-Tags als Ziel.
- Aktionen wie ausblenden, markieren oder verschieben.
- Tag-Zaehler in der Sidebar.

## Datenmodell

`Rule` bleibt das zentrale SwiftData-Model. Es erhaelt neue Properties:

- `conditionMatchMode: String` mit Werten `all` fuer AND und `any` fuer OR.
- `conditions: [RuleCondition]` als Cascade-Relationship.

`RuleCondition` wird als neues SwiftData-Model angelegt:

- `id: UUID`
- `field: String` mit Werten `title`, `summary`, `feedTitle`.
- `conditionOperator: String` mit Werten `contains`, `startsWith`, `endsWith`.
- `value: String`
- `sortOrder: Int`
- `rule: Rule?`

Die bisherigen Felder `conditionField`, `conditionOperator` und `conditionValue`
bleiben vorerst am `Rule`-Model, damit vorhandene Daten und Tests nicht hart
brechen. Ein Backfill-Service legt fuer alte Regeln genau eine `RuleCondition` an,
wenn eine Regel noch keine Conditions besitzt. Danach nutzt neue Logik nur noch
`conditions`; der Altbestand bleibt als Kompatibilitaetsanker bestehen.

## Wizard

Der Wizard ist ein SwiftUI-Sheet und wird fuer Erstellen und Bearbeiten wiederverwendet.

Schritte:

1. Modus: Einfach oder Power User.
2. Bedingungen:
   - Einfach: eine Bedingung mit Feld, Operator und Wert.
   - Power User: mehrere Bedingungen, jede mit Feld, Operator und Wert.
   - Power User waehlt zusaetzlich `AND` oder `OR`.
3. Ziel: vorhandenes Tag auswaehlen oder direkt ein neues Tag mit Farbe erstellen.
4. Zusammenfassung: Name, Aktiv/Inaktiv, Bedingungen, Match-Modus und Ziel-Tag
   pruefen und speichern.

Beim Bearbeiten oeffnet derselbe Wizard mit den gespeicherten Werten. Beim Einstieg
aus einem Artikel werden Vorschlaege vorausgefuellt:

- Feedname als moegliche Bedingung `feedTitle contains <Feedtitel>`.
- Signifikantes Titelwort als moegliche Bedingung `title contains <Wort>`.
- Ziel-Tag bleibt bewusst leer, damit keine falsche Automatisierung entsteht.

## Einstellungen

`SettingsView` erhaelt einen Abschnitt `Regeln`.

Die Liste zeigt fuer jede Regel:

- Name.
- Aktiv/Inaktiv-Toggle.
- Ziel-Tag mit Farbe.
- Kurzbeschreibung wie `3 Bedingungen · AND`.
- Button zum Bearbeiten.
- Loeschen mit Bestaetigung.

Ein Button `Regel erstellen` oeffnet den Wizard ohne Artikel-Kontext. Die Einstellungen
sind die zentrale Verwaltungsstelle fuer Regeln.

## Sidebar

Die Sidebar ist kein Verwaltungsort fuer Regeln. Sie zeigt nur eine kompakte
Rule-Section:

- Anzahl aktiver Regeln.
- Button oder Link `Regel aus aktuellem Artikel erstellen`, wenn ein Artikel
  ausgewaehlt ist.
- Der Einstieg oeffnet den Wizard mit Artikel-Kontext.

Wenn kein Artikel ausgewaehlt ist, bleibt der Einstieg deaktiviert oder wird nicht
angezeigt. Die Sidebar soll dadurch ruhig bleiben und nicht zur zweiten
Regelverwaltung werden.

## Architektur

Neue Bausteine:

- `RuleCondition.swift`: SwiftData-Model fuer einzelne Bedingungen.
- `RuleMatchMode.swift`: kleine String-Enum-Hilfe fuer `all` und `any`.
- `RuleConditionField.swift`: Anzeigenamen und gespeicherte Werte fuer Felder.
- `RuleConditionOperator.swift`: Anzeigenamen und gespeicherte Werte fuer Operatoren.
- `RuleViewModel.swift`: Create/Edit/Delete/Validation und Backfill-freundliche
  Normalisierung.
- `RuleConditionBackfillService.swift`: einmaliger Backfill alter Regeln.
- `RuleWizardView.swift`: Erstellen und Bearbeiten.
- `RuleSettingsView.swift`: Liste in den Einstellungen.

`RuleEngine` bleibt ein Service und bekommt nur die Mehrbedingungen-Logik. UI-Code
kennt die Engine nicht direkt; er speichert nur gueltige Regeln in SwiftData.

## Fehler- und Randfaelle

Eine Regel braucht mindestens eine gueltige Bedingung, ein Ziel-Tag und einen Namen.
Leere Bedingungswerte werden nicht gespeichert. Unbekannte Felder oder Operatoren
werden von der Engine weiterhin als Nicht-Treffer behandelt, damit alte oder kuenftige
Daten nicht den Feed-Refresh abbrechen.

`AND` trifft nur, wenn alle gueltigen Bedingungen treffen. `OR` trifft, wenn mindestens
eine gueltige Bedingung trifft. Hat eine Regel nach Migration oder Datenkorruption
keine gueltige Bedingung, trifft sie nicht.

## Tests

Fokussierte Tests:

- `RuleEngine` trifft bei `AND` nur, wenn alle Bedingungen passen.
- `RuleEngine` trifft bei `OR`, wenn mindestens eine Bedingung passt.
- Ungueltige oder leere Bedingungen treffen nicht.
- Backfill erzeugt aus alten einfachen Rule-Feldern genau eine Condition.
- `RuleViewModel` verhindert Speichern ohne Name, Ziel-Tag oder Bedingung.
- `RuleViewModel` kann Regeln erstellen, bearbeiten, deaktivieren und loeschen.
- Feed-Refresh taggt neue Artikel weiterhin ueber die neue Mehrbedingungen-Engine.

Abschlussverifikation:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -skip-testing:FeedivoUITests -derivedDataPath /private/tmp/feedivo-m3-rule-wizard-derived-data
```

## Dokumentation

Nach Umsetzung werden `AGENTS.md` und `docs/FEATURES.md` aktualisiert:

- M3-Regel-UI als fertig markieren.
- Multi-Condition-Regeln mit AND/OR dokumentieren.
- Sidebar-Rolle klar beschreiben: Anzeige und Artikel-Kontext-Einstieg, keine
  Verwaltung.
- Offen halten: Regex, Rueckwirkendes Anwenden, verschachtelte Gruppen, weitere
  Aktionen.
