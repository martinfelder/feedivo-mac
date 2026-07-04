# SQLite Large Dataset Performance – Lasttest Ergebnis (2026-07-04)

## Ziel
Prüfen, ob der produktive SwiftUI-Snapshot-Pfad bei größerer Datenmenge stabil und schnell genug bleibt.

## Test-Scope
- Datei: `FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift`
- Datensatz im Testgenerator:
  - 100 Feeds
  - 600 Artikel pro Feed
  - alternierende Read-Markierung
- Assertions gegen harte Schwellen in der Suite:
  - `timeline` All Scope < `1.8s`
  - `timeline` Feed-Scope < `0.9s`
  - `search` < `0.9s`
  - `setRead + reload` < `0.4s`
  - Feed-Unread-Summen > `1.5s`

## Ausführung
Getestet mit:

```bash
xcodebuild test \
  -project Feedivo.xcodeproj \
  -scheme Feedivo \
  -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SQLiteLargeDatasetPerformanceTests/timelineQueriesSindUnterLastbedingungenSchnell \
  -only-testing:FeedivoTests/SQLiteLargeDatasetPerformanceTests/readsUmschaltenUndTimelineNeuLadenIstEffizient \
  -only-testing:FeedivoTests/SQLiteLargeDatasetPerformanceTests/sidebarUndArtikelCountsLassenSichSchnellBerechnen
```

und Einzelausführungen für jedes der drei Szenarien als Fallback.

## Ergebnis
- `EXIT: 0`, Test-Suite vollständig grün (PASS).
- Alle drei Performance-Zeitschwellen in der Testlogik wurden erfolgreich erreicht.
- Die Ergebnisse sind reproduzierbar und bestätigen aktuell die Beibehaltung des SwiftUI-Snapshot-Wegs.

## Entscheidung
- Kein AppKit-/NSTableView-Refactor erforderlich.
- NetNewsWire-nahes Verhalten bei großen Datensätzen ist mit den aktuellen Schwellwerten ausreichend.
- Nächster Schritt: Fokus auf weitere `FeedivoApp`-Produktivitätsblöcke (Phase 8, Blocker-Beseitigung), nicht auf Timeline-UI-Retruktur.
