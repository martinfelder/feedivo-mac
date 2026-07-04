# SQLite Large Dataset Performance – Lasttest Ergebnis (2026-07-04)

## Ziel
Prüfen, ob der produktive SwiftUI-Snapshot-Pfad (`TimelineStore`, `SQLiteReaderState`, `ArticleStatusStore`) auch bei großem Datenvolumen stabil bleibt.

## Test-Scope
- Datei: `FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift`
- Datensatz (Testgenerator in der Suite):
  - 100 Feeds
  - 600 Artikel pro Feed
  - inkl. alternierenden Read-Markierungen

## Ausführung
Befehl:

```bash
xcodebuild test \
  -project Feedivo.xcodeproj \
  -scheme Feedivo \
  -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SQLiteLargeDatasetPerformanceTests \
  -enableCodeCoverage NO
```

## Ergebnis

- Der Lauf startet korrekt in der Build-Pipeline.
- Die Testausführung hängt am Ende auf dem Test-Finish-Loop (XCTest/Runner-Recovery).
- Damit liegt aktuell **kein vollständiges PASS/FAIL-Ergebnis** vor.
- Die Lasttestlogik in `FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift` ist implementiert und einsatzbereit.

## Nächster Schritt

1. Testlauf mit alternativer Testausführungsweise wiederholen (z. B. andere Runner-Parameter oder alternative Maschine).
2. Sobald der Lauf vollständig durchläuft, Messwerte in diese Datei nachtragen.
3. Entscheidung nach NetNewsWire-Vergleich treffen:
   - SwiftUI-Snapshot bleibt aktuell genug: kein AppKit-Timeline-Refactoring.
   - Bei Leistungsgrenzen: separaten Plan für AppKit-Timeline aufsetzen.
