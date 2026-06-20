# Feed Properties Design

## Ziel

Feedivo bekommt im Kontextmenue eines Feeds einen neuen Eintrag `Feed Eigenschaften...`.
Die Ansicht zeigt technische und organisatorische Informationen zu einem Feed und
erlaubt als erste editierbare Option das Aktualisierungsintervall.

## Einstieg

- Der Eintrag erscheint im Rechtsklick-Kontextmenue einer Feed-Zeile oberhalb von
  `Feed loeschen`.
- Der Eintrag oeffnet ein macOS-typisches Sheet aus der Sidebar heraus.
- Das Sheet ist eine ruhige Eigenschaftenansicht mit zweispaltiger Darstellung:
  links die Bezeichnung, rechts der Wert oder die passende Kontrolle.

## Angezeigte Felder

- `Original Titel`: der Feed-Titel aus den Feed-Metadaten.
- `Website`: Website-URL aus Feed-Metadaten, sofern vorhanden.
- `XML Adresse`: gespeicherte Feed-URL.
- `Gefolgt ab`: neues gespeichertes Datum, gesetzt beim Hinzufuegen eines Feeds.
- `Ordner`: Platzhalter `Kein Ordner`; das Ordner-Feature wird als eigener Ausbau geplant.
- `Letzter Artikel`: der zuletzt veroeffentlichte gespeicherte Artikel des Feeds.
- `Aktualisierungsintervall`: editierbar, nutzt `Feed.refreshIntervalMinutes`.
- `Naechster Abruf`: berechnet aus `lastRefreshed + refreshIntervalMinutes`, sofern moeglich.
- `Zuletzt aktualisiert`: `Feed.lastRefreshed`.
- `Feed Log`: letzte 20 Log-Eintraege fuer Abrufe, neue Artikel und Fehler.

## Datenmodell

`Feed` wird um vorbereitende Metadaten erweitert:

- `siteURL: String?`
- `followedAt: Date?`
- `folderName: String?`

`FeedLogEntry` wird als neues SwiftData-Modell ergaenzt:

- `id: UUID`
- `createdAt: Date`
- `kind: String`
- `message: String`
- `feed: Feed?`

Die Relationship vom Feed zu Log-Eintraegen verwendet Cascade-Loeschen, damit Logs mit
dem Feed entfernt werden. Es werden hoechstens die letzten 20 Eintraege pro Feed angezeigt.

## Verhalten

- Beim Hinzufuegen eines Feeds wird `followedAt` gesetzt.
- Wenn Feed-Metadaten eine Website enthalten, wird `siteURL` gespeichert.
- Beim erfolgreichen Aktualisieren wird ein Feed-Log-Eintrag geschrieben.
- Wenn neue Artikel gefunden werden, nennt der Log-Eintrag die Anzahl.
- Bei Refresh-Fehlern wird ein Fehler-Log-Eintrag geschrieben.
- Bestehende Feeds duerfen leere Werte haben; die UI zeigt dafuer einen neutralen Platzhalter.
- `Aktualisierungsintervall` wird im Eigenschaften-Sheet angepasst und direkt gespeichert.

## Ordner-Feature

Ordner werden in dieser Iteration nicht voll implementiert. Das Eigenschaften-Sheet zeigt
das Feld bereits an, damit die spaetere Produktstruktur sichtbar ist. Die eigentliche
Ordnerverwaltung bleibt ein separater Feature-Backlog-Ausbau.

## Lokalisierung

Alle sichtbaren Texte werden in `Localizable.xcstrings` fuer Deutsch, Englisch,
Franzoesisch und Italienisch erfasst und ueber `L10n.swift` bereitgestellt.

## Tests und Verifikation

- Unit-Tests fuer Feed-Eigenschaften-Formatierung und naechsten Abruf.
- Unit-Tests fuer Feed-Log-Begrenzung auf die letzten 20 Eintraege.
- Build-Verifikation mit `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`.
- Passende fokussierte Unit-Tests mit `xcodebuild test`.
