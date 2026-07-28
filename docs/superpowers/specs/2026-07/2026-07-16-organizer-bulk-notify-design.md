# Spec: Bulk-Benachrichtigungsverwaltung im Feed-Organizer

**Datum:** 2026-07-16
**Status:** Genehmigt, bereit für leichtgewichtige Direktumsetzung (kein voller Subagent-Driven-Development-Prozess — Feature ist klein und reine Wiederverwendung bestehender Bausteine)

## Problem

Um die Benachrichtigung für einen Feed umzuschalten, musste der Nutzer bisher jeden Feed einzeln über
"Feed-Eigenschaften" öffnen (`FeedPropertiesView.notificationToggleRow`). Es gibt keine Möglichkeit, das
für mehrere oder alle Feeds auf einmal zu tun.

## Lösung

Erweiterung von `Feedivo/Views/Organizer/FeedManagementOrganizerView.swift` (nutzt bereits Mehrfachauswahl
über `selectedFeedIDs: Set<String>` und die bestehenden "Sichtbare auswählen"/"Auswahl leeren"-Buttons als
Vorbild für Bulk-Operationen):

1. **Pro-Zeile Glocken-Button** in `FeedManagementOrganizerRow`, links neben dem bestehenden
   Papierkorb-Button. Icon `bell.fill` wenn `feed.isNotificationEnabled == true`, sonst `bell.slash`
   (Status auf einen Blick erkennbar, kein Tooltip nötig — analog zum reinen Icon-Button-Stil des
   Trash-Buttons, `.plain`-Style). Klick ruft direkt
   `FeedStore(database:).updateNotificationEnabled(id: feed.id, isEnabled: !feed.isNotificationEnabled)`
   auf, danach `SQLiteDataInvalidation.bumpStatusVersion()` + Reload der Elternliste (gleiches Muster wie
   der bestehende Lösch-Pfad).

2. **Zwei neue Toolbar-Buttons** in der bestehenden `FlowLayout`-Toolbar, rechts vom "Ausgewählte
   löschen"-Button: "Benachrichtigen (N)" und "Nicht benachrichtigen (N)" mit Glocken-Icon und
   Anzahl-Suffix bei aktiver Auswahl — exakt das gleiche `RuleDialogButton`-Muster wie der bestehende
   Löschen-Button (`.disabled(selectedFeeds.isEmpty)` + `.opacity(0.45)` wenn leer). Beide iterieren über
   `selectedFeeds` und rufen `updateNotificationEnabled` pro Feed auf (feste `true`/`false`-Zielwerte,
   kein Toggle-per-Feed), dann einmalig `loadFeeds()`.

3. **"Alle Feeds"** wird bewusst nicht separat implementiert — durch "Sichtbare auswählen" (bei leerer
   Suche = alle Feeds) + einen der beiden Bulk-Buttons bereits abgedeckt.

4. **Kein neuer Store-Code.** `FeedStore.updateNotificationEnabled(id:isEnabled:)` existiert bereits
   (`Feedivo/Stores/FeedStore.swift:122`) und wird nur an drei neuen Stellen wiederverwendet.

5. **Fehlerbehandlung:** Wiederverwendung des bestehenden `errorMessage`-`@State` in
   `FeedManagementOrganizerView` — bei einem Fehler während der Bulk-Schleife bricht die Schleife ab und
   zeigt die Fehlermeldung, exakt wie `deleteFeeds(_:)` es heute schon macht.

6. **Keine Bestätigungs-Dialoge.** Anders als beim Löschen ist das Umschalten der Benachrichtigung
   jederzeit reversibel — kein `confirmationDialog` nötig.

## Neue L10n-Keys

Namensschema `settings.feeds.*`, analog zu den bestehenden Keys in diesem Bereich:

- `settings.feeds.notifySelected` — Toolbar-Button "Benachrichtigen (N)"
- `settings.feeds.unnotifySelected` — Toolbar-Button "Nicht benachrichtigen (N)"
- `settings.feeds.row.enableNotification` — Tooltip/Accessibility-Label Zeilen-Button (deaktiviert → aktiviert)
- `settings.feeds.row.disableNotification` — Tooltip/Accessibility-Label Zeilen-Button (aktiviert → deaktiviert)

## Out of Scope

- Keine Änderung an `FeedPropertiesView.notificationToggleRow` (bleibt als Einzel-Feed-Weg bestehen).
- Keine neue Store-Methode, keine Datenbank-Migration — reine UI-Erweiterung auf bestehender Datenschicht.
- Kein separater "Alle Feeds"-Button (siehe Punkt 3 oben).
