# M3 Background Refresh Design

## Entscheidung

Feedivo verbessert den bestehenden automatischen Refresh mit dem macOS-nativen
`NSBackgroundActivityScheduler`. Es wird keine Launch-Agent-, Login-Item- oder
Helper-App-Loesung fuer komplett beendete Apps gebaut.

Der automatische Refresh bleibt damit systemfreundlich: Er laeuft, wenn Feedivo
offen oder im Hintergrund ist. macOS entscheidet den genauen Zeitpunkt.

## Ziele

- Den aktuellen Scheduler-Pfad robuster und besser nachvollziehbar machen.
- Statusdaten speichern, damit User und Entwickler sehen koennen, wann der letzte
  automatische Refresh lief und ob er erfolgreich war.
- Die Einstellungen ehrlicher machen: Der Refresh ist automatisch, aber nicht
  minutengenau und startet eine beendete App nicht neu.
- Bestehenden manuellen Refresh-Kern weiterverwenden, damit Regeln, Favicons,
  Feed-Logs und Fehlerbehandlung konsistent bleiben.

## Nicht-Ziele

- Kein Refresh nach komplett beendeter App.
- Keine Login Items, Launch Agents oder Menubar-Helper.
- Keine Push-Benachrichtigungen in diesem Schritt.
- Keine pro-Feed-Scheduler. Die globalen Settings bleiben die Quelle fuer den
  automatischen Refresh; pro-Feed-Intervalle bleiben sichtbare Metadaten und koennen
  spaeter in eine feinere Strategie einfliessen.

## Verhalten

Wenn automatischer Refresh deaktiviert ist, wird der Scheduler invalidiert.

Wenn automatischer Refresh aktiviert ist:

- Feedivo plant beim App-Start den Background Scheduler.
- Aenderungen an Ein/Aus oder Intervall planen den Scheduler neu.
- Der Scheduler nutzt das konfigurierte Intervall und eine grosszuegige Toleranz,
  damit macOS Energie und Netzwerk sinnvoll buendeln kann.
- Beim Ausfuehren wird derselbe Pfad wie `Alle Feeds aktualisieren` verwendet.
- Nach Abschluss werden Statusdaten gespeichert:
  - letzter automatischer Refresh-Zeitpunkt
  - Ergebnis `success` oder `failed`
  - optionale Fehlermeldung
  - ungefaehr naechster geplanter Zeitpunkt

## UI

In den Einstellungen unter automatischem Refresh wird ein kurzer Status angezeigt:

- Letzter automatischer Refresh
- Status des letzten Laufs
- Naechster geplanter Refresh als ungefaehre Zeit
- Ein Hinweis, dass macOS den genauen Zeitpunkt bestimmt und Feedivo laufen muss

Die UI bleibt kompakt. Kein separates Dashboard.

## Architektur

- `BackgroundRefreshSettings` bekommt zusaetzliche UserDefaults-Keys fuer Statusdaten.
- `BackgroundRefreshService` kapselt das Schreiben des Status.
- `SystemBackgroundActivityRefreshScheduler` bleibt der einzige echte Scheduler.
- `FeedivoApp` plant weiterhin beim Start und bei Settings-Aenderungen.
- Tests decken Planung, Deaktivierung, Statusberechnung und Statusspeicherung ab.

## Fehlerbehandlung

Einzelne Feed-Fehler bleiben im bestehenden `FeedViewModel.refreshAllFeeds`-Pfad
gekapselt. Der Background-Status speichert, ob der Lauf insgesamt ohne fatalen
Abbruch abgeschlossen wurde. Wenn der Refresh-Pfad eine Fehlermeldung setzt, kann
diese als letzter Background-Fehler gespeichert werden.

Scheduler-Fehler beim Planen werden nicht prominent als Alert gezeigt, aber als
Status fuer Entwickler/User nachvollziehbar abgelegt.

## Tests

- `BackgroundRefreshSettingsTests` fuer neue Status-Defaults und Datumsberechnung.
- `BackgroundRefreshServiceTests` fuer:
  - deaktivierter Refresh invalidiert Scheduler
  - aktivierter Refresh plant erwartete Request-Daten
  - Statusdaten werden nach Erfolg gespeichert
  - Fehlerstatus wird mit Meldung gespeichert

## Dokumentation

`AGENTS.md` und `docs/FEATURES.md` werden nach der Umsetzung aktualisiert:

- M3 Background Refresh wird als erledigt markiert.
- Die macOS-Grenze bleibt dokumentiert: keine Ausfuehrung nach komplett beendeter App.
