# SQLite-First Admin Views Design

## Ziel

Die teilweise migrierten Verwaltungsoberflächen werden SQLite-first: Feed-/Sidebar-Verwaltung, TagManager, Regelverwaltung und Smart-Folder-Verwaltung sollen ihre produktive Listen- und Speicherschicht aus GRDB-Stores beziehen. SwiftData bleibt nur als Übergangs-, Backfill- oder noch nicht produktiv entfernbarer Container erhalten.

## Architektur

Die vorhandenen SQLite-Tabellen und Stores bleiben die Grenze: `TagStore`, `FeedFolderStore`, `SQLiteRuleStore` und `SQLiteSmartFolderStore` speichern Definitionen und liefern leichte Snapshots/Records. SwiftUI-Views sollen keine `@Query` auf `Tag`, `Rule`, `SmartFolder` oder `FeedFolder` mehr als produktive Quelle verwenden. Wo Views aktuell SwiftData-Objekte als Identität oder Sheet-Payload verwenden, werden String-IDs beziehungsweise Records eingesetzt.

`FeedivoApp` darf den SwiftData-Container weiter starten, weil Feeds, alte Backfills und einige Übergangspfade ihn noch brauchen. Der Umbau entfernt deshalb nicht SwiftData insgesamt, sondern trennt die Admin-Editoren vom SwiftData-Produktpfad.

## Komponenten

- `TagManagerView` lädt und mutiert `TagRecord`s direkt über `TagStore`.
- `SidebarView` nutzt SQLite-Snapshots/Records für Tags, Feed-Ordner und Smart-Folder-Definitionen. Feed-Kontextmenüs dürfen vorerst SwiftData-Feeds verwenden, solange Feed-Löschung/-Eigenschaften noch daran hängen.
- `RuleSettingsView` und `RuleWizardView` nutzen `SQLiteRuleStore`, `TagStore` und `RuleEngine.RuleSnapshot` statt SwiftData-`Rule`.
- `SmartFolderSettingsView` und `SmartFolderEditorView` nutzen `SQLiteSmartFolderStore` und `SmartFolderRecord`/`SmartFolderConditionRecord`.
- Source-Tests dokumentieren, dass diese Views keine SwiftData-`@Query` auf die migrierten Verwaltungsmodelle mehr verwenden.

## Tests

Die Umsetzung erfolgt testgetrieben über Source-Tests und fokussierte Store-/State-Tests. Jeder View-Block bekommt zuerst einen roten Test, danach minimale ViewModel-/Store-Erweiterungen, danach Build. Die bestehenden SQLiteAdminStoreTests bleiben die Datenbank-Absicherung.

## Bewusst nicht enthalten

SwiftData-Container-Entfernung ist kein Teil dieses Designs. Sie kommt erst, wenn auch Feed-Erstellung, Feed-Eigenschaften, alte Backfills und verbleibende Legacy-Views keinen produktiven SwiftData-Pfad mehr benötigen.
