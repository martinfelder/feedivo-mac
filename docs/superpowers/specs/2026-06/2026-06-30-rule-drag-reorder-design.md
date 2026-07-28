# Rule Drag Reorder Design

## Ziel

Regeln in den Einstellungen sollen per Drag & Drop neu sortiert werden können. Die bestehenden Hoch-/Runter-Buttons bleiben erhalten, weil sie präzise und barriereärmer sind.

Der anschließende letzte 5.2-Slice ergänzt außerdem `Regex` als Operator für Regelbedingungen.

## Design

Die Regelliste übernimmt das vorhandene Drag-&-Drop-Muster der Smart-Folder-Einstellungen: Eine gezogene Zeile merkt sich ihre `UUID`, andere Zeilen nehmen lokale Text-Drops an, und beim Überfahren einer Zielzeile wird die `sortOrder` aller Regeln normalisiert. Damit verwenden Pfeilbuttons, Drag & Drop und die spätere Regel-Auswertung dieselbe Reihenfolge.

Die UI zeigt während des Ziehens eine leicht reduzierte Deckkraft und eine kompakte Drag-Vorschau mit Griff-Icon und Regelname. Die vorhandene Spalte `Reihenfolge` bleibt sichtbar; der Griff dient als natürliches visuelles Signal.

Regex-Bedingungen werden in derselben RuleEngine wie die bestehenden Operatoren ausgewertet. Patterns sind case-insensitive; ungültige Regexe werden beim Speichern abgelehnt und matchen in der Vorschau nicht.

## Tests

Die neue Sortierlogik wird in `RuleViewModelTests` testgetrieben abgedeckt. Die UI selbst nutzt das bereits etablierte SwiftUI-Pattern aus `SmartFolderSettingsView`.
