# Artikelliste: Feed-Status-Zeile im Header — Design

## Kontext

Im Artikellisten-Header (`SQLiteFeedArticleListView.swift`, `articleListHeader`) stehen
aktuell zwei Zeilen: der Feed-/Titel-Name (`navigationTitle`) und die Anzahl ungelesener
Artikel (`unreadArticleCountText`). Wenn ein einzelner Feed ausgewählt ist (`scope == .feed`),
soll darunter eine dritte Zeile ergänzt werden, die anzeigt, wann der Feed zuletzt
erfolgreich aktualisiert wurde — oder, falls der letzte Aktualisierungsversuch fehlschlug,
den konkreten Fehlergrund.

Auslöser: Nutzer-Report vom 2026-07-12 — der Wunsch nach sichtbarer Information zum
Aktualisierungsstatus direkt im Artikellisten-Header, zusätzlich zur bereits bestehenden
orangenen Fehler-Banner-Leiste (`feedErrorBanner`), die nur bei nicht-leerer Artikelliste
und mit generischem Text ohne Fehlergrund erscheint.

## Bereits vorhandene Datenbasis (keine Schema-Änderung nötig)

- `FeedRecord.lastRefreshedAt: Date?` (`Feedivo/Database/Records/FeedRecord.swift`) —
  Zeitpunkt der letzten *erfolgreichen* Aktualisierung.
- `feed_logs`-Tabelle / `FeedLogRecord` (`Feedivo/Database/Records/FeedLogRecord.swift`) —
  `level` ("info"/"error"), `message` (Klartext, bei Fehlern bereits mit
  `error.localizedDescription` befüllt, siehe `SQLiteFeedRefreshService.swift:167`),
  `createdAt`.
- `FeedLogStore.logs(feedID:limit:)` (`Feedivo/Stores/FeedLogStore.swift`) — liefert die
  neuesten Log-Einträge eines Feeds, `ORDER BY createdAt DESC`. Mit `limit: 1` liefert das
  genau den letzten Aktualisierungsversuch (egal ob erfolgreich oder fehlgeschlagen).
- `Date.feedivoDisplay(mode:)` (`Feedivo/Extensions/Date+RelativeDisplay.swift`) —
  app-weit bereits genutzte Datumsformatierung, respektiert die bestehende
  Relativ-/Absolut-Einstellung aus Feature 19.1 (`ArticleDateDisplayMode`).

## Verhalten der neuen Zeile

**Sichtbarkeit:** Nur wenn `scope == .feed` (ein einzelner Feed ist ausgewählt). Bei
Tags/Smart Filtern/Intelligenten Ordnern (mehrere Feeds gleichzeitig, kein einzelner
sinnvoller Zeitstempel) bleibt der Header wie bisher unverändert (zwei Zeilen).

**Drei Zustände, abhängig vom neuesten `feed_logs`-Eintrag des Feeds:**

1. **Kein Log-Eintrag vorhanden** (Feed wurde noch nie aktualisiert, z. B. gerade erst
   hinzugefügt): Zeile bleibt komplett ausgeblendet. Header hat weiterhin nur zwei Zeilen.
2. **Neuester Eintrag hat `level == "info"`** (letzter Versuch erfolgreich): Zeile zeigt
   „Zuletzt aktualisiert: {Datum}" in sekundärer/grauer Farbe (wie die Ungelesen-Zeile).
   `{Datum}` = `FeedRecord.lastRefreshedAt` formatiert über `Date.feedivoDisplay(mode:)`.
3. **Neuester Eintrag hat `level == "error"`** (letzter Versuch fehlgeschlagen, auch wenn
   frühere Versuche erfolgreich waren): Zeile zeigt „Konnte nicht aktualisiert werden:
   {Grund}" in orange (wie die bestehende Fehler-Banner-Leiste). `{Grund}` = `message` des
   neuesten Log-Eintrags.

**Verhältnis zur bestehenden `feedErrorBanner`-Leiste:** Bleibt unverändert bestehen (Nutzer-
Entscheid). Im Fehlerfall mit nicht-leerer Artikelliste erscheinen dann sowohl die neue
Header-Zeile als auch die Banner-Leiste — bewusst akzeptierte Redundanz, kein Widerspruch.

## Datenabruf

Die bestehende `reload()`-Methode (Fall `.feed` in
`SQLiteFeedArticleListView.swift:497-510`) ruft aktuell `FeedStore.hasRecentError(feedID:)`
auf (liefert nur `Bool`, für die bestehende Banner-Sichtbarkeit). Diese Abfrage wird durch
einen `FeedLogStore.logs(feedID:limit:1)`-Aufruf ersetzt, der sowohl `level` (für die
Banner-Sichtbarkeit UND den neuen Zustand 2 vs. 3) als auch `message` (für den Fehlergrund
in Zustand 3) liefert — ein Query-Aufruf statt vorher indirekt zwei. `lastRefreshedAt` wird
zusätzlich aus `FeedStore` (bzw. dem bereits geladenen `FeedRecord` des Feeds) gelesen.

**Reaktivität:** Kein neuer Mechanismus nötig. `reload()` wird bereits heute bei jeder
Statusänderung (`sqliteStatusVersion`, Teil des bestehenden `scopeToken`/`loadToken`) erneut
aufgerufen — jeder Feed-Refresh bumpt `SQLiteDataInvalidation.bumpStatusVersion()`
(`FeedViewModel.swift`), was automatisch einen `reload()` auslöst und damit auch die neue
Zeile aktuell hält.

## UI-Details

- Position: dritte Zeile in `articleListHeader`'s `VStack(alignment: .leading, spacing: 2)`,
  nach der Ungelesen-Zeile.
- Schriftgröße/-stil analog zur Ungelesen-Zeile (`interfaceTextSize.font(size: 13)`,
  `.lineLimit(1)`).
- Farbe: `.secondary` im Erfolgsfall, `.orange` im Fehlerfall (konsistent mit
  `feedErrorBanner`s bestehender Farbwahl).
- Neue L10n-Keys (de/en/fr/it, wie Projektkonvention): Formatstring für „Zuletzt
  aktualisiert: %@" und „Konnte nicht aktualisiert werden: %@".

## Out of Scope

- Keine Änderung an der bestehenden `feedErrorBanner`-Leiste selbst.
- Keine Anzeige für Tag-/Smart-Filter-/Smart-Folder-Scopes (mehrere Feeds).
- Keine neue Datenbank-Migration — alle benötigten Felder existieren bereits.
- Keine Änderung an `FeedStore.hasRecentError` selbst — bleibt unangetastet bestehen.
  Verifiziert: `SQLiteFeedArticleListView.swift:507` ist der einzige direkte Aufrufer
  dieser Methode (wird durch den neuen `FeedLogStore.logs(feedID:limit:1)`-Aufruf
  ersetzt); `FeedSidebarSnapshot.hasRecentError` (Sidebar-Fehler-Badge,
  `FeedRowView.swift:51`) ist ein separates, JOIN-basiertes Feld derselben Semantik,
  aber ein eigener Code-Pfad und bleibt unberührt. `hasRecentError` selbst ist zudem
  direkt in `SQLiteFeedStoreTests.swift` getestet — bleibt als API bestehen.
