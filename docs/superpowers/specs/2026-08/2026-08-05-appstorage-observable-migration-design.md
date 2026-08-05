# Design: `@AppStorage`→`@Observable`-Migration für SQLite-Invalidierung

**Datum:** 2026-08-05
**Status:** Zur Review

## Kontext

Im direkt vorangegangenen Debugging (siehe CLAUDE.md „Aktuell in Arbeit", Eintrag
2026-08-05 „Reader-Ladeverzögerung") wurde per Live-`OSLog`-Messung (`log stream`)
festgestellt: nach dem Beheben von zwei anderen Ursachen (redundante Dreifach-Ladevorgänge
im Reader, GRDB-`DatabaseQueue`-Read-Kontention) bleibt eine sehr konstante
~220-250ms-Lücke zwischen dem Abschluss einer Statusänderung (z. B. Artikel als gelesen
markieren) und dem Moment, in dem irgendeine View darauf reagiert. Zweifelsfrei
nachgewiesen: mehrere unabhängige `.onChange`/`.task(id:)`-Beobachter (Artikelliste UND
Reader) feuern exakt zur gleichen Millisekunde — sie blockieren sich nicht gegenseitig,
sondern warten beide auf denselben vorgelagerten Effekt. Bei einer Auswahl, die KEINEN
Status-Bump auslöst (Artikel bereits gelesen), sinkt die Gesamtzeit auf ~120-140ms.

Root Cause: SwiftUIs `@AppStorage`/`UserDefaults`-Änderungsbenachrichtigung selbst hat
auf diesem System eine konsistente ~220-250ms-Latenz, bevor `.onChange`/`.task(id:)`-
Observer reagieren — vermutlich verschärft durch die Zahl der gleichzeitig auf denselben
Key registrierten `@AppStorage`-Beobachter (mindestens 7 Views für
`SQLiteDataInvalidation.statusVersionKey` allein).

## Ziel

`SQLiteDataInvalidation` (Status-Änderungen: Gelesen/Stern/Archiviert/Feed-/Regel-/
Ordner-Mutationen) und `SidebarBadgeInvalidation` (direkte Artikel→Tag-Zuweisungen,
die nicht über den Feed laufen) von `UserDefaults`-basierter `@AppStorage`-Beobachtung
auf natives SwiftUI-`@Observable` umstellen, um die App-weite Reaktivitäts-Latenz auf
das technisch erreichbare Minimum zu senken — ohne die bestehende
„keine `@Query`/Observation-Automatik, UI-Updates laufen explizit über Bump+Observe"-
Architektur (siehe ADR-007-Kontext) grundsätzlich zu verändern.

## Betrachtete Ansätze

1. **Globales `@MainActor @Observable`-Singleton pro Invalidierungstyp (gewählt).**
   Folgt dem bereits dreifach etablierten Muster in diesem Projekt
   (`FeedJumpKeyMonitor`, `TextEditingFocusMonitor`, `SparkleUpdateCoordinator`:
   `@Observable @MainActor final class X { static let shared = X() }`). Direkteste,
   für den Zweck gebaute Lösung — SwiftUIs Observation-Framework ist nativ ins
   Render-Diffing eingehängt, keine Umleitung über eine Persistenz-API. Behebt
   nebenbei eine latente Race Condition: der aktuelle Bump
   (`defaults.set(defaults.integer(forKey:) + 1, forKey:)`) ist ein nicht-atomares
   Read-Modify-Write: Bumpen zwei Threads gleichzeitig, kann ein Increment verloren
   gehen. Eine `@MainActor`-isolierte `Int`-Property macht das strukturell
   unmöglich.
2. **Dependency-Injection statt Singleton.** Signal-Objekt wird explizit durch
   Stores/Services durchgereicht (wie `FeedivoDatabase`). Theoretisch bessere
   Testisolation, aber für ein wirklich app-weites, immer-vorhandenes Signal würde
   das Boilerplate durch 20+ Konstruktoren ohne kommensurablen Mehrwert einführen —
   die Testisolation lässt sich bei Ansatz 1 günstiger über eine `reset()`-Methode
   erkaufen.
3. **`NotificationCenter` statt `@Observable`.** Kleinerer Code-Diff (`UserDefaults`
   bleibt Speicher, zusätzlich synchrones `NotificationCenter`-Post beim Bump,
   Views abonnieren per `.onReceive`). Verworfen: bricht mit dem etablierten
   `@Observable`-Muster, behält das nicht-atomare Bump-Pattern bei, und ob das die
   gemessene Latenz zuverlässig behebt, ist unbewiesen (nur `@AppStorage`s
   Verhalten wurde tatsächlich gemessen, nicht `NotificationCenter`s).

**Entscheidung:** Ansatz 1 — kleinster, konsistentester Diff, technisch am direktesten
für das Problem gebaut, behebt eine latente Race Condition als Nebeneffekt.

## Architektur

Beide Typen bleiben eigenständige Klassen (kein Zusammenlegen zu einem gemeinsamen
Signal-Objekt — konzeptionell unabhängig, ein Zusammenlegen wäre unnötige Kopplung):

```swift
@MainActor
@Observable
final class SQLiteDataInvalidation {
    static let shared = SQLiteDataInvalidation()
    private init() {}

    private(set) var statusVersion = 0

    func bumpStatusVersion() {
        statusVersion += 1
    }

    /// Nur für Tests: isoliert aufeinanderfolgende Testfälle voneinander,
    /// analog zum bereits bestehenden `-parallel-testing-enabled NO`-Workaround
    /// für `UserDefaults.standard`-Races in diesem Projekt.
    func reset() {
        statusVersion = 0
    }
}
```

Analog für `SidebarBadgeInvalidation` (`Feedivo/Views/Sidebar/SidebarUnreadCount.swift`):
`shared.directTagVersion` / `bumpDirectTagVersion()` / `reset()`.

## Datenfluss & Actor-Isolation

- **Views:** `@AppStorage(SQLiteDataInvalidation.statusVersionKey) private var
  sqliteStatusVersion = 0` entfällt vollständig. Stattdessen direkter Zugriff auf
  `SQLiteDataInvalidation.shared.statusVersion` in `body`/`.onChange(of:)` —
  SwiftUIs Observation-Tracking erkennt den Zugriff automatisch, kein Property-
  Wrapper nötig. Betrifft ~15 `@AppStorage`-Deklarationen in ~12 View-Dateien.
- **Aufrufer, die bereits auf dem MainActor laufen** (wegen projektweitem
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` die klare Mehrheit): Aufruf selbst
  ändert sich nicht, nur `SQLiteDataInvalidation.bumpStatusVersion()` (statisch) wird
  zu `SQLiteDataInvalidation.shared.bumpStatusVersion()` (Instanzmethode).
- **Nicht-MainActor-Aufrufer:** werden explizit `async`/MainActor-isoliert
  umgebaut (Nutzerentscheidung: kein verstecktes `Task { @MainActor in ... }`-
  Hopping innerhalb der Bump-Funktion selbst — jeder betroffene Aufrufer wird
  einzeln sichtbar angepasst). Bislang konkret bestätigt: `CloudSyncEngine.
  backfillAllExistingRecords` (`nonisolated static func`) — deren einziger
  Produktiv-Aufrufort (`CloudSyncEngine.swift:128`) läuft aber bereits in einem
  MainActor-Kontext (direkt danebenstehend: `self.syncEngine = engine`), nur die
  Funktionsdeklaration selbst müsste ihr `nonisolated` verlieren. Die vollständige
  Liste weiterer tatsächlich nicht-MainActor-Aufrufer ist erst beim
  Implementieren abschließend feststellbar — der Compiler zeigt das zuverlässig
  bei jedem einzelnen der 23 betroffenen Aufrufer.

## Migrationsumfang

23 betroffene Produktivdateien:
- 19 Aufrufer von `SQLiteDataInvalidation.bumpStatusVersion()`
- 4 Aufrufer von `SidebarBadgeInvalidation.bumpDirectTagVersion()`
- ~15 `@AppStorage`-Deklarationen in ~12 View-Dateien (teils dieselben Dateien wie
  oben, da manche Views sowohl bumpen als auch beobachten)

Umsetzung über den etablierten Subagent-Driven-Development-Prozess. Sinnvolle
Task-Aufteilung (finale Reihenfolge/Gruppierung wird im Implementierungsplan
festgelegt, nicht hier): Kern-Typen (`SQLiteDataInvalidation`/
`SidebarBadgeInvalidation` selbst) zuerst, danach Views (größte Gruppe, rein
mechanisch), danach Stores/Services (kleinere Gruppe, hier liegt das Actor-
Isolation-Risiko), CloudSync als eigene, isolierte letzte Gruppe (höchste
Historie an actor-isolation-bezogenen Bugs in diesem Projekt, siehe CLAUDE.md-
Gotchas zu `Task.detached`/`CKSyncEngine`-Reentrancy).

## Testing

Zwei konkrete, beim Design-Gespräch bereits identifizierte Testfolgen:

- `FeedViewModelTests.swift` liest/schreibt aktuell direkt `UserDefaults.standard`
  über `SQLiteDataInvalidation.statusVersionKey` (inkl. Save/Restore-Logik um den
  Testlauf herum), um zu verifizieren, dass ein Bump stattgefunden hat. Wird auf
  direktes Lesen von `SQLiteDataInvalidation.shared.statusVersion` (vorher/nachher-
  Vergleich, `reset()` im Test-Setup statt Save/Restore) umgestellt.
- `FeedivoAppSceneConfigurationTests.swift` enthält mindestens 3 Source-Sniffing-
  Tests (String-Match auf den exakten Quelltext, bekanntes Testmuster in diesem
  Projekt), die auf den alten Code-Text prüfen:
  `"@AppStorage(SQLiteDataInvalidation.statusVersionKey)"`,
  `"SQLiteDataInvalidation.bumpStatusVersion()"`,
  `"SidebarBadgeInvalidation.bumpDirectTagVersion()"`. Diese brechen zwangsläufig
  und werden auf die neue Aufrufsyntax angepasst (keine Regression, reines
  Nachziehen).
- Neue `reset()`-Methode (testonly) auf beiden Singletons für Testisolation
  zwischen aufeinanderfolgenden Testfällen.
- Nach Abschluss: gezielter Regressionslauf über alle Suiten, die
  `SQLiteDataInvalidation`/`SidebarBadgeInvalidation` direkt oder indirekt über
  betroffene Stores/Views berühren, plus Live-Verifikation der ursprünglich
  gemessenen Reader-Ladezeit (`log stream`-Methode aus der vorangegangenen
  Debugging-Session, TEMP-DEBUG-Pattern, danach wieder entfernt) — Erwartung:
  deutliche Annäherung an die ~120-140ms-Bestzeit (aktuell nur bei „kein Bump
  nötig"-Selektionen erreicht) auch für Selektionen, die einen Status-Bump
  auslösen.

## Risiken

Größter unbekannter Faktor beim Schreiben dieser Spec: wie viele der 23 Aufrufer
tatsächlich nicht-MainActor sind (aktuell nur einer konkret bestätigt,
`CloudSyncEngine.backfillAllExistingRecords`, und dessen Produktiv-Aufrufer ist
bereits MainActor). Das entscheidet, wie groß der tatsächliche Async-Umbau wird —
der Compiler macht jeden betroffenen Fall aber unmittelbar sichtbar, kein
Blindflug. CloudSync-Dateien haben in diesem Projekt die höchste bekannte Dichte an
bereits einmal gefundenen Actor-Isolation-/Reentrancy-Bugs (siehe CLAUDE.md-
Gotchas) — verdienen deshalb besondere Sorgfalt bzw. eine eigene, isolierte
Task-Gruppe im Implementierungsplan statt Vermischung mit den mechanischeren
View-Änderungen.
