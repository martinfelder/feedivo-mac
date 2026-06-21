# Feedivo macOS - Feature Roadmap

> Diese Datei ist die versionierte Produkt-Roadmap fuer Feedivo.
> Sie fasst die Feature-Liste, Codex-Feedback und die aktuelle Priorisierung zusammen.
> Bei jeder Feature-, Architektur- oder Roadmap-Aenderung muss diese Datei geprueft
> und bei Bedarf nachgefuehrt werden.

Status-Legende:
- `In Diskussion`: Idee ist erfasst, Details offen.
- `Entschieden`: Feature soll grundsaetzlich kommen.
- `In Arbeit`: Aktuell im Milestone.
- `Fertig`: Nutzbare Basis ist implementiert.
- `Zurueckgestellt`: Bewusst nicht fuer die naechsten Milestones geplant.

Prioritaets-Legende:
- `MVP`: Noetig fuer eine erste wirklich brauchbare Version.
- `v1`: Wichtig, aber nach dem MVP.
- `Spaeter`: Gute Idee, aber bewusst nicht frueh bauen.

---

## Produkt-Richtung

Feedivo soll zuerst ein schneller, nativer und angenehmer macOS RSS Reader werden.
Die App soll sich wie eine Mac-App anfuehlen: 3-Spalten-Layout, gute Tastaturbedienung,
kontextnahe Aktionen, ruhige UI, kein Web-App-Gefuehl.

Die langfristige Vision umfasst Tags, Regeln, iCloud Sync, OPML, Smart Filter,
Reader-Modi, Suche und spaeter auch Statistiken/Export. Fuer die Umsetzung gilt:
erst Lesen und Feed-Verwaltung stabil machen, dann Organisation, dann Sync und Komfort.

---

## MVP-Schnitt

Diese Features haben Vorrang, weil sie Feedivo aus einem Prototyp zu einem nutzbaren
RSS Reader machen:

1. Artikelzeile verbessern: Titel, Datum, Zusammenfassung, ungelesen-Indikator.
2. Gelesen/Ungelesen markieren, inklusive Tastaturkuerzel.
3. Artikel mit Stern markieren.
4. Vorheriger/naechster Artikel, inklusive Tastaturbedienung. ✅ Basis umgesetzt.
5. Manueller Refresh fuer aktuellen Feed und alle Feeds.
6. Feed loeschen mit Bestaetigung. ✅ Basis umgesetzt.
7. Smart Filter: Alle, Ungelesen, Mit Stern, Heute. ✅ Basis umgesetzt.
8. OPML Import.
9. Einfache Einstellungen: Refresh-Intervall, Standard-Reader-Modus, Schriftgroesse.
   Erste Einstellung ist bereits vorhanden: Artikel beim Oeffnen automatisch als
   gelesen markieren; automatischer Refresh kann ebenfalls konfiguriert werden.

Nicht in den MVP gehoeren Spotlight, Statistiken, Drittanbieter-Integrationen,
Feed-Suche per externem Dienst, komplexe intelligente Ordner und Background Refresh
bei geschlossener App.

---

## Aktueller Stand

### Fertig

- M1 Foundation ist abgeschlossen.
- FeedKit ist eingebunden.
- SwiftData Modelle fuer Feed, Article, Tag und Rule existieren.
- Feed per Feed-URL hinzufuegen funktioniert als Basis.
- Feeds koennen ueber den Sidebar-Plus-Button oder ueber `Feed > Feed hinzufügen...`
  mit `Cmd+N` hinzugefuegt werden; beide Wege nutzen dasselbe Sheet.
- Feed-Titel wird aus Feed-Metadaten gelesen.
- Sidebar zeigt gespeicherte Feeds.
- Artikel-Liste zeigt echte Artikel eines Feeds.
- Reader zeigt Feedname, ungefaehre Lesezeit, Artikelalter, Titel, native
  Reader-Bloecke, Vor/Zurueck-Navigation und Original-Link.
- Die Reader-Darstellung ist als ruhiger Editorial Reader gesetzt: kleinerer
  semibold Titel, bewusstere Blockabstaende, kontrollierte Lead-Bildhoehe und
  dezenter Original-Link im Footer.
- In der Reader-Toolbar kann ein rechter Metadaten-Inspector eingeblendet werden;
  dort sind Feed-Ordner und Artikel-Tags sichtbar und bearbeitbar, waehrend der
  Artikelkopf nur Feedname, Lesezeit und Zeitpunkt zeigt.
- Reader-Rendering wandelt HTML/Plain-Text in Absätze und Bildbloecke.
- ArticleRowView zeigt Titel, Datum, Summary, optionales Bild, Ungelesen-Punkt
  rechts oben und Stern rechts unten.
- Artikelbilder werden beim Feed-Parsing robuster aus Media RSS, iTunes Image,
  Bild-Enclosures und HTML-Content extrahiert; relative Bild-URLs werden zu absoluten
  URLs normalisiert. Falls ein Feed-Item kein Bild enthaelt, kann Feedivo die
  verlinkte Artikelseite pruefen und `og:image`/`twitter:image` als Artikelbild
  uebernehmen.
- Artikel koennen per Kontextmenue gelesen/ungelesen und per Stern-Button markiert
  werden.
- Artikelaktionen koennen auch per macOS-Menue `Artikel` und Tastaturkuerzeln
  gesteuert werden: `Cmd+Shift+U` fuer gelesen/ungelesen, `Cmd+D` fuer Stern.
- Feeds koennen per Rechtsklick in der Sidebar oder ueber das macOS-Menue `Feed`
  geloescht werden; vor dem Loeschen erscheint eine Bestaetigung mit Hinweis auf
  die mitgeloeschten Artikel.
- Der ausgewaehlte Feed kann per macOS-Menue `Feed` oder `Cmd+R` manuell aktualisiert
  werden; neue Artikel werden ohne Duplikate hinzugefuegt.
- Alle Feeds koennen per macOS-Menue `Feed` oder `Cmd+Shift+R` manuell aktualisiert
  werden; einzelne Feed-Fehler stoppen den Gesamtlauf nicht und werden gesammelt
  gemeldet.
- Automatisches Gelesen-Markieren beim Oeffnen ist standardmaessig aktiv und in den
  Einstellungen abschaltbar.
- i18n Foundation ist umgesetzt: String Catalog mit Deutsch, Englisch, Franzoesisch
  und Italienisch, plus zentraler `L10n.swift` Helper.
- In den Einstellungen kann die App-Sprache auf `Nach System`, Deutsch, Englisch,
  Franzoesisch oder Italienisch gesetzt werden.
- In den Einstellungen kann die app-weite Oberflaechenschrift auf Klein, Standard,
  Gross oder Sehr gross gestellt werden. Diese UI-Groesse ist bewusst getrennt von
  der Reader-Typografie und skaliert Sidebar, Feed-Zeilen, Artikelzeilen und Settings
  sichtbar ueber konkrete Font-/Icon-/Zeilenwerte.
- In der Artikelansicht koennen Titel- und Fliesstext-Schrift ueber kuratierte
  Presets direkt per Toolbar-Popover und in den Einstellungen getrennt gewaehlt werden;
  Fliesstext-Groesse, Titel-/Fliesstext-Zeilenabstand und Artikelbreite sind dort
  ebenfalls einstellbar. Die Metazeile oberhalb des Titels nutzt die
  Fliesstext-Schrift proportional kleiner.
- Automatischer Refresh ist als macOS-native Basis umgesetzt: In den Einstellungen
  kann er aktiviert und auf 15, 30, 60 oder 120 Minuten gestellt werden. Feedivo nutzt
  `NSBackgroundActivityScheduler`; macOS entscheidet den genauen Zeitpunkt und startet
  eine vollstaendig beendete App dafuer nicht neu.
- Favicons werden beim Hinzufuegen und Aktualisieren per HTML Discovery erkannt,
  in `Feed.faviconURL` gespeichert und in der Sidebar angezeigt; `/favicon.ico`
  bleibt Fallback, externe Favicon-Dienste werden nicht genutzt.
- Smart Filter sind in der Sidebar umgesetzt: Alle Artikel, Ungelesen, Mit Stern
  und Heute zeigen feeduebergreifend die passenden gespeicherten Artikel. Die
  Filter-Icons haben passende Farben: blau, tuerkis, gelb und gruen.
- Die linke Sidebar nutzt das umgesetzte Design 11 aus den Reader-Prototypen:
  dunkler Hintergrund, dezente Auswahlflaeche, bestehende Smart-Filter-Icons und
  weiterhin helle Artikel-Liste/Reader-Spalten.
- Artikel-Links koennen kopiert und Originalartikel im Standardbrowser geoeffnet
  werden; die Aktionen sind im Artikel-Kontextmenue, Reader und macOS-Menue `Artikel`
  verfuegbar. In der Artikelansicht oeffnet auch ein Klick auf den Titel den
  Originalartikel, sofern ein gueltiger Link vorhanden ist.
- Feed Eigenschaften sind als Basis umgesetzt: Rechtsklick auf einen Feed oeffnet
  ein lokalisiertes Sheet mit Feed-Header, Statusmetriken, Metadaten, editierbarem
  Aktualisierungsintervall, naechstem Abruf, letztem Artikel, Kopierbutton fuer die
  XML-Adresse und den neuesten 20 Feed-Log-Eintraegen.
- Vorheriger/naechster Artikel ist als Basis umgesetzt: Reader-Toolbar und
  macOS-Menue `Artikel` navigieren mit `Cmd+↑`/`Cmd+↓` innerhalb der aktuell sichtbaren
  Feed- oder Smart-Filter-Liste; am Listenrand gibt es keinen Loop.
- OPML Import/Export ist umgesetzt: Import liest `.opml`/`.xml`, ueberspringt
  Duplikate anhand der Feed-URL, uebernimmt OPML-Gruppen als `folderName` und
  aktualisiert neu importierte Feeds direkt ueber den normalen Refresh-Pfad;
  Export schreibt die aktuelle Feed-Liste als `Feedivo.opml`.
- Einfache Ordnerverwaltung ist umgesetzt: Feeds stehen in der Sidebar-Section
  `Ordner`, der Section-Titel hat einen + Button zum Erstellen neuer Ordner,
  leere Ordner werden als `FeedFolder` gespeichert, Ordner sind aufklappbar,
  Feeds in Ordnern sind eingerueckt, und der Ordnername kann in den Feed-Eigenschaften
  bearbeitet oder geleert werden.
- Projekt baut und Unit-Tests laufen; UI-Test-Runner blockierte lokal am 2026-06-19
  vor dem App-Launch an einer alten Feedivo-PID.

### Aktuell in Arbeit

M2 Core Features:
- Naechster Backlog-Ausbau: Tag-/Regel-Basis.

---

## Feature-Backlog

### 1. Reader

#### 1.1 Anzeigemodus
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Standard bleibt der native SwiftUI Reader. Die globale Einstellung
  `readerDisplayMode` kann zwischen Nativer Reader und Originalansicht wechseln.
- Originalansicht: `WebContentView` laedt den Originalartikel per `WKWebView`, sofern
  ein gueltiger Artikellink vorhanden ist.
- Fallback: Fehlt ein gueltiger Link, zeigt Feedivo automatisch den nativen Reader.
- Zugriff: Picker in den Einstellungen unter Lesen und segmentierter Umschalter in der
  Reader-Toolbar.
- Spaeter: Modus pro Artikel oder pro Feed merken, falls sich das nach Nutzung sinnvoll
  anfuehlt.

#### 1.1.1 Native Reader Rendering
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: `ReaderContentRenderer` erzeugt Absätze, Ueberschriften, Zitate,
  Listenpunkte und Bildbloecke aus gespeicherten Feed-Inhalten; `ReaderView` rendert
  diese Bloecke nativ mit SwiftUI.
- Metadaten: Oberhalb des Titels zeigt `ReaderView` Feedname, ungefaehre Lesezeit
  und Artikelalter, sofern die Daten vorhanden sind.
- Design-Exploration: Unter `docs/design/article-reader-prototypes/index.html`
  liegen zehn interaktive Reader-Varianten als Entscheidungsgrundlage fuer die
  spaetere visuelle Ueberarbeitung der Artikelansicht.
- Reduzierte Folge-Exploration: Unter
  `docs/design/article-reader-minimal-step/index.html` liegen drei bewusst ruhige
  Varianten fuer die Positionierung von Feedname, Lesezeit, Ordner und Tags, weil
  die Schriftarten selbst bereits individuell konfigurierbar sind.
- Implementierte Richtung: Feedname, Lesezeit und Zeitpunkt bleiben im Artikelkopf;
  Ordner und Tags liegen in einem einblendbaren rechten Inspector und koennen dort
  bearbeitet werden.
- Visuelle Richtung: Die Artikelansicht bleibt reduziert und inhaltsnah; seltenere
  Aktionen wie `Link kopieren` liegen im Mehr-Menue, damit die Toolbar ruhiger bleibt.
- Fallback: Leere strukturierte HTML-Bloecke werden verworfen; kaputte oder unbekannte
  Inhalte fallen auf normale Absätze zurueck.
- Naechster Schritt: Klickbare Inline-Links separat planen und umsetzen.

#### 1.2 Navigation Vor/Zurueck
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Buttons in der Reader-Toolbar und macOS-Menue `Artikel` mit
  `Cmd+↑` fuer vorherigen und `Cmd+↓` fuer naechsten Artikel.
- Verhalten: Navigation laeuft innerhalb der aktuell sichtbaren Feed- oder
  Smart-Filter-Liste und stoppt am Listenrand ohne Loop.
- Entscheidung: Oeffnen markiert standardmaessig automatisch als gelesen. Benutzer
  koennen die Option in den Einstellungen deaktivieren.

#### 1.3 Gelesen/Ungelesen
- Status: Fertig als Basis
- Prioritaet: MVP
- Basis: Manuell per Kontextmenue, automatisch beim Oeffnen mit Einstellung,
  per Artikel-Menue und per Tastaturkuerzel `Cmd+Shift+U`.
- Spaeter: "Alle als gelesen" pro Feed und Smart Filter.

#### 1.4 Stern/Favoriten
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Stern ist per Button, Kontextmenue, Artikel-Menue und `Cmd+D`
  schaltbar. Noch kein separates Archiv im MVP.
- Smart Filter "Mit Stern" gehoert dazu.

#### 1.5 Tags manuell zuweisen
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Artikel-Tags koennen im rechten Reader-Inspector hinzugefuegt und
  vom aktuellen Artikel entfernt werden; vorhandene Tags werden wiederverwendet und
  neue Tags als `Tag` gespeichert.
- Offen: Tag-Farben, Tag-Manager, Feed-Tags und Sidebar-Filter folgen separat.

#### 1.6 Artikel teilen
- Status: Entschieden
- Prioritaet: v1
- Empfehlung: macOS Share Sheet mit Titel und URL. Summary optional spaeter.

#### 1.7 Im Browser oeffnen
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Originalartikel werden ueber den macOS-Standardbrowser geoeffnet.
  Zugriff ueber klickbaren Reader-Titel, Reader-Toolbar, Artikel-Kontextmenue und
  macOS-Menue `Artikel`.

#### 1.8 Safari-Reader-aehnliche Ansicht
- Status: In Diskussion
- Prioritaet: Spaeter
- Empfehlung: Nicht mit dem nativen Feed-Content-Reader verwechseln. Die erste native
  Rendering-Basis existiert; Readability/Extraktion erst spaeter, weil es deutlich mehr
  Fehlerfaelle erzeugt.

#### 1.9 Schriftgroesse
- Status: Fertig als Basis
- Prioritaet: MVP/v1
- Implementiert: Globale Fliesstext-Groesse fuer den nativen Reader, direkt im
  Reader-Popover und in den Einstellungen unter Lesen. Wertebereich: 14...24 px.
- Entscheidung: Zunaechst nur Fliesstext-Groesse, Titelgroesse bleibt fest.

#### 1.9.1 Schriftarten
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Getrennte Reader-Presets fuer Titel und Fliesstext: System, Geist,
  Inter, Manrope, DM Sans, Literata, Newsreader, IBM Plex Sans, Atkinson Hyperlegible,
  Source Serif 4, Libre Franklin, Lora, Merriweather, Noto Sans, Noto Serif,
  Roboto Slab, Crimson Pro, Fraunces, Serif.
- Zugriff: Direkt in der Artikelansicht via Toolbar-Popover und zusaetzlich in den
  Einstellungen unter Lesen.
- Hinweis: Custom-Fonts werden per bekannten PostScript-Namen verwendet; falls eine
- Schrift auf dem Mac nicht verfuegbar ist, greift die App auf gebundelte Fontdateien
  aus `Feedivo/Resources/Fonts/` zurueck. Font-Herkunft und Lizenzen sind in
  `docs/THIRD_PARTY_FONTS.md` dokumentiert.

#### 1.9.2 Zeilenabstand
- Status: Fertig als Basis
- Prioritaet: MVP/v1
- Implementiert: Separater Titel-Zeilenabstand (0...10 px) und Fliesstext-
  Zeilenabstand (1...12 px) fuer den nativen Reader, direkt im Reader-Popover
  und in den Einstellungen unter Lesen.

#### 1.9.3 Artikelbreite
- Status: Fertig als Basis
- Prioritaet: MVP/v1
- Implementiert: Maximale Breite der Artikelansicht als Slider im Reader-Popover
  und in den Einstellungen unter Lesen. Default: 720 px, Wertebereich: 520...980 px.

#### 1.10 Link kopieren
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Artikel-Link in die macOS-Zwischenablage kopieren. Zugriff in
  Reader-Toolbar, Artikel-Kontextmenue und macOS-Menue `Artikel`.

#### 1.11 Regel aus Artikel erstellen
- Status: Entschieden
- Prioritaet: v1
- Empfehlung: Erst nach Tag- und Regel-Basis. Vorausfuellen aus Feed, Titel-Wort und URL.

### 2. Artikel-Liste

#### 2.1 Artikel anzeigen
- Status: Fertig
- Prioritaet: MVP
- Implementiert: `ArticleRowView` mit Titel, Datum, Summary, Statuspunkt, Stern und
  optionalem Bild.
- Bildbasis: `FeedService` speichert absolute `Article.imageURL` Werte aus Media RSS,
  iTunes Image, Bild-Enclosures, JSON Feed Bildern oder HTML-`img` Quellen. Wenn ein
  RSS-Item kein Bild enthaelt, nutzt `fetchFeed` als Fallback die Metabilder der
  verlinkten Artikelseite (`og:image`/`twitter:image`).

#### 2.2 Sortierung
- Status: In Diskussion
- Prioritaet: MVP
- Empfehlung: Standard "neueste zuerst". Umschaltbar spaeter.

#### 2.3 Filterung
- Status: In Diskussion
- Prioritaet: MVP
- Empfehlung: Erst Smart Filter in Sidebar, danach Listenfilter.

#### 2.4 Kontextmenue
- Status: Fertig als Basis
- Prioritaet: MVP/v1
- Implementiert: Rechtsklick mit gelesen/ungelesen, Stern, Link kopieren und
  Original oeffnen.
- Naechster Schritt: "Alle als gelesen" pro Feed und Smart Filter.

### 3. Sidebar

#### 3.1 Feed-Liste
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Feed-Titel mit Favicon aus `Feed.faviconURL`; Fallback ist das
  RSS-Systemsymbol.
- Design: Dunkle linke Sidebar nach Prototyp Design 11; aktive Zeilen werden nur
  dezent aufgehellt, damit die linke Spalte ruhig bleibt.
- Ordner: Feeds stehen in der Section `Ordner`; Feeds mit `folderName` werden unter
  einem Ordnerkopf gruppiert, Feeds ohne Ordner bleiben direkt in dieser Section.
  Neben dem Section-Titel erstellt ein + Button neue leere Ordner. Feeds innerhalb
  eines Ordners werden eingerueckt angezeigt; Ordner sind per Chevron auf- und
  zuklappbar.
- Offen: Ungelesen-Zaehler, Drag & Drop fuer Ordner.

#### 3.2 Smart Filter
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Sidebar-Filter fuer Alle Artikel, Ungelesen, Mit Stern und Heute.
  Die Artikelliste nutzt dafuer alle gespeicherten Artikel statt nur einen Feed.
  Die Filter-Icons sind farbig und passen semantisch zum jeweiligen Symbol.
- Entscheidung: Die bestehenden SF-Symbol-Icons bleiben auch im dunklen Sidebar-Design
  erhalten; nur Hintergrund und Auswahlstil wurden geaendert.
- Spaeter: Eigene Smart Filter und weitere Zeitfilter wie Gestern.

#### 3.3 Tag-Abschnitt
- Status: In Diskussion
- Prioritaet: v1
- Empfehlung: Unterhalb von Smart Filtern und Feeds, feeduebergreifend.

### 4. Feed-Verwaltung

#### 4.1 Feed hinzufuegen
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Sidebar-Plus-Button und macOS-Menue `Feed > Feed hinzufügen...`
  mit `Cmd+N`; beide Wege oeffnen dasselbe `AddFeedSheet`. Beim Speichern wird das
  Favicon der Website per HTML Discovery ermittelt.
- Offen: Auto-Erkennung, Vorschau.

#### 4.2 Feed bearbeiten
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Feed kann per Rechtsklick in der Sidebar ueber `Feed umbenennen...`
  einen eigenen Anzeigenamen bekommen. Der urspruengliche Feed-Name wird separat in
  `Feed.originalTitle` gespeichert und kann im Dialog wiederhergestellt werden.
- Entscheidung: Refresh aktualisiert den gespeicherten Originalnamen, ueberschreibt
  aber keinen manuell gesetzten Anzeigenamen.
- Offen: URL eher nicht frei aendern ohne erneute Validierung.

#### 4.2.1 Feed Eigenschaften
- Status: Fertig als Basis
- Prioritaet: MVP/v1
- Implementiert: Rechtsklick auf Feed zeigt `Feed Eigenschaften...`. Die Ansicht hat
  einen Feed-Header mit Icon/Favicon-Fallback, Website und Statusmetriken sowie eine
  gruppierte Detailansicht mit editierbarem Aktualisierungsintervall.
- Inhalt: Originaltitel, Website, XML-Adresse mit Kopierbutton, Gefolgt-ab-Datum,
  editierbarer Ordner, letzter Artikel, Aktualisierungsintervall, naechster Abruf,
  zuletzt aktualisiert und die neuesten 20 Feed-Log-Eintraege.
- Log: Feed hinzufuegen, erfolgreiche Aktualisierung und Refresh-Fehler werden in
  SwiftData als `FeedLogEntry` gespeichert; pro Feed bleiben die neuesten 20 Eintraege.
- Ordner: Der Ordnername wird direkt im Sheet bearbeitet; leere Eingaben entfernen
  den Ordner vom Feed.

#### 4.3 Feed loeschen
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Rechtsklick auf Feed in der Sidebar und macOS-Menue `Feed` mit
  deaktivierter Aktion ohne Auswahl.
- Verhalten: Bestaetigungsdialog mit Hinweis, dass alle gespeicherten Artikel des
  Feeds mitgeloescht werden; bei geloeschter Auswahl werden Feed und Artikel-Detail
  zurueckgesetzt.
- Spaeter: Optional Shortcut nur dann pruefen, wenn sich das nicht zu gefaehrlich anfuehlt.

#### 4.4 Manueller Refresh
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Ausgewaehlten Feed ueber macOS-Menue `Feed` oder `Cmd+R`
  aktualisieren; alle Feeds ueber macOS-Menue `Feed` oder `Cmd+Shift+R`
  aktualisieren.
- Verhalten: Feed-Metadaten und `lastRefreshed` werden aktualisiert; neue Artikel
  werden angehaengt, bestehende Artikel werden anhand Link beziehungsweise
  Titel+Datum nicht dupliziert.
- Verhalten bei allen Feeds: Wenn ein Feed fehlschlaegt, werden die restlichen Feeds
  weiter aktualisiert; am Ende wird eine Sammelmeldung mit den betroffenen Feednamen
  gesetzt.
- Offen: Sichtbarer Fortschritt.

#### 4.5 Automatischer Refresh
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Globaler automatischer Refresh ueber `NSBackgroundActivityScheduler`
  mit Einstellung fuer Ein/Aus und Intervalle 15, 30, 60 oder 120 Minuten.
- Verhalten: Nutzt denselben Refresh-Pfad wie `Alle Feeds aktualisieren`; einzelne
  Feed-Fehler stoppen den Gesamtlauf nicht.
- Einschraenkung: macOS bestimmt den exakten Ausfuehrungszeitpunkt. Vollstaendig
  beendete Apps werden fuer diese Basis nicht neu gestartet, weil `BGTaskScheduler`
  fuer native macOS Apps nicht verfuegbar ist.

### 5. Tags und Regeln

#### 5.1 Tags verwalten
- Status: In Arbeit
- Prioritaet: v1
- Stand: Artikel-Tags koennen im Reader-Inspector als Basis hinzugefuegt und
  entfernt werden.
- Offen: Name/Farbe zentral verwalten, Feeds taggen und Tags in der Sidebar filtern.

#### 5.2 Automatische Regeln
- Status: Entschieden
- Prioritaet: v1
- Empfehlung: Erst einfache Regeln: Feld, Operator, Wert, Aktion "Tag zuweisen".
- Regex, Mehrfachbedingungen und Ausblenden spaeter.

### 6. iCloud Sync

#### 6.1 CloudKit Sync
- Status: In Diskussion
- Prioritaet: v1/spaeter
- Empfehlung: Erst aktivieren, wenn Datenmodell und Grundfeatures stabil sind.
- Sync-Umfang: Feeds, gelesen, Stern, Tags, Regeln. Artikel-Content genau pruefen wegen Speicher.

### 7. OPML

#### 7.1 OPML Import
- Status: Fertig als Basis
- Prioritaet: MVP
- Umsetzung: macOS-Dateiimport fuer `.opml`/`.xml`; Duplikate werden anhand der
  normalisierten Feed-URL uebersprungen. Neue Feeds werden direkt nach dem Import
  ueber den normalen Refresh-Pfad aktualisiert.
- Hinweis: OPML-Gruppen werden als `Feed.folderName` gespeichert und dadurch direkt
  in der Sidebar gruppiert.

#### 7.2 OPML Export
- Status: Fertig als Basis
- Prioritaet: v1
- Umsetzung: Exportiert die aktuelle Feed-Liste als OPML 2.0 mit gruppierten Feeds
  und XML-escaping.

### 8. Einstellungen

#### 8.1 Allgemein
- Status: Fertig als Basis
- Prioritaet: MVP/v1
- Implementiert: Einstellung "Artikel beim Oeffnen als gelesen markieren" sowie
  automatischer Refresh mit Ein/Aus und Intervallauswahl.
- Naechster Schritt: Standard-Reader-Modus.
- Automatisches Loeschen spaeter.

#### 8.2 Darstellung
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: App-weite Oberflaechenschriftgroesse, Reader-Schriften,
  Fliesstext-Groesse sowie Titel- und Fliesstext-Zeilenabstand und Artikelbreite.
- Entscheidung: UI-Schriftgroesse und Reader-Typografie bleiben getrennt, damit
  die App-Bedienung groesser werden kann, ohne die Artikel-Leseeinstellungen zu
  veraendern.
- Umsetzung: Die UI-Groesse nutzt `InterfaceTextSize` mit eigenen Skalierungswerten,
  weil fest gestaltete macOS-Zeilen nicht verlaesslich allein ueber `DynamicTypeSize`
  sichtbar mitskalieren.
- Naechster Schritt: Theme System/Hell/Dunkel spaeter.

### 9. Suche

#### 9.1 Volltext-Suche
- Status: Entschieden
- Prioritaet: v1
- Empfehlung: Erst Titel + Summary + Content in SwiftData. Suchfeld oben in Artikelliste.

#### 9.2 Suchfilter
- Status: In Diskussion
- Prioritaet: Spaeter
- Empfehlung: Nach einfacher Suche.

#### 9.3 Spotlight
- Status: In Diskussion
- Prioritaet: Spaeter
- Empfehlung: Nicht fuer MVP/v1.

### 10. Benachrichtigungen

#### 10.1 Neue Artikel
- Status: Entschieden
- Prioritaet: v1/spaeter
- Empfehlung: Erst wenn Refresh stabil ist. Zusammengefasste Benachrichtigung statt pro Artikel.

#### 10.2 Einstellungen
- Status: In Diskussion
- Prioritaet: Spaeter
- Empfehlung: Nach Basis-Benachrichtigung.

### 11. Lesedauer

#### 11.1 Lesedauer
- Status: Entschieden
- Prioritaet: v1
- Empfehlung: ca. Minuten im Reader und eventuell in Artikelzeile. Basis 200 Woerter/Minute.

#### 11.2 Lesefortschritt
- Status: In Diskussion
- Prioritaet: Spaeter
- Empfehlung: Erst nach Reader-Polish.

### 12. Feed hinzufuegen erweitert

#### 12.1 Feed per URL
- Status: Fertig als Basis
- Prioritaet: MVP
- Offen: Validierung/Preview verbessern.

#### 12.2 Auto-Erkennung aus Webseiten-URL
- Status: In Diskussion
- Prioritaet: v1
- Empfehlung: HTML `link rel=alternate` auslesen. Bei mehreren Feeds Auswahl anzeigen.

#### 12.3 Feed-Suche
- Status: In Diskussion
- Prioritaet: Spaeter
- Empfehlung: Nicht frueh bauen; externe Dienste koennen Abhaengigkeiten und API-Probleme bringen.

#### 12.4 Drag & Drop
- Status: In Diskussion
- Prioritaet: Spaeter

#### 12.5 Feed-Vorschau
- Status: In Diskussion
- Prioritaet: v1
- Empfehlung: Nach Feed-URL-Validierung; 3-5 Artikel anzeigen.

### 13. Feed-Metadaten

#### 13.1 Feed-Infos
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Basis-Metadaten wie Titel, Beschreibung, Website-URL fuer
  Favicon-Discovery und `faviconURL` werden beim Feed-Parsing beziehungsweise
  Hinzufuegen/Aktualisieren gepflegt.
- Hinweis: Der Originaltitel aus den Feed-Metadaten wird getrennt vom Anzeigenamen
  gespeichert, damit benutzerdefinierte Feed-Namen erhalten bleiben.

#### 13.2 Feed-Gesundheit
- Status: In Diskussion
- Prioritaet: MVP/v1
- Empfehlung: Fehlerstatus in Feed speichern, Badge/Tooltip spaeter anzeigen.

### 14. Statistiken

#### 14.1 Lese-Statistiken
- Status: Entschieden
- Prioritaet: Spaeter
- Empfehlung: Nicht frueh bauen, weil zuerst verlaessliche Leseereignisse gebraucht werden.

#### 14.2 Feed-Statistiken
- Status: In Diskussion
- Prioritaet: Spaeter

#### 14.3 Daten exportieren
- Status: In Diskussion
- Prioritaet: Spaeter

### 15. Feeds organisieren

#### 15.1 Ordner
- Status: Fertig als Basis
- Prioritaet: v1/spaeter
- Implementiert: Maximal eine Ebene. Feed gehoert zuerst nur in einen Ordner.
  Sidebar zeigt die Section `Ordner` mit + Button fuer neue Ordner; leere Ordner
  werden als `FeedFolder` gespeichert, Feed-Zuordnung erfolgt weiter ueber
  `Feed.folderName`; Ordner sind aufklappbar und Feeds innerhalb eines Ordners sind
  eingerueckt. Bearbeitung der Feed-Zuordnung erfolgt in den Feed-Eigenschaften.
- Spaeter: Drag & Drop, Umbenennen/Loeschen als eigene Ordneraktionen und
  Ungelesen-Zaehler pro Ordner.

#### 15.2 Drag & Drop organisieren
- Status: In Diskussion
- Prioritaet: Spaeter

#### 15.3 OPML-Gruppen als Ordner
- Status: Fertig als Basis
- Prioritaet: v1/spaeter
- Umsetzung: OPML-Gruppen werden beim Import als `Feed.folderName` gespeichert und
  dadurch direkt in der Sidebar gruppiert.

### 16. Intelligente Ordner

#### 16.1 Intelligenter Ordner
- Status: Entschieden
- Prioritaet: Spaeter
- Empfehlung: Erst nach Tags, Suche und Smart Filtern.

#### 16.2 Erstellen/Bearbeiten
- Status: In Diskussion
- Prioritaet: Spaeter

### 17. Archivieren und Aufraeumen

#### 17.1 Archiv
- Status: Entschieden
- Prioritaet: Spaeter
- Empfehlung: Fuer v1 Stern als "merken" nutzen, Archiv spaeter sauber abgrenzen.

#### 17.2 Automatisches Loeschen
- Status: In Diskussion
- Prioritaet: Spaeter
- Empfehlung: Erst wenn Archiv/Stern-Konzept geklaert ist.

### 18. Artikel exportieren

#### 18.1 Einzelartikel
- Status: Entschieden
- Prioritaet: v1/spaeter
- Empfehlung: Erst Markdown/Text, PDF spaeter.

#### 18.2 Batch-Export
- Status: In Diskussion
- Prioritaet: Spaeter

#### 18.3 Drittanbieter
- Status: In Diskussion
- Prioritaet: Spaeter
- Empfehlung: Zuerst macOS Share Sheet, keine direkte Integration fuer MVP.

### 19. Sonstige Ideen

- Menubar-Icon: Spaeter.
- Vollstaendige Tastaturnavigation: MVP/v1, weil sehr mac-like.

### 20. Mehrsprachigkeit

#### 20.1 i18n Foundation
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: `Localizable.xcstrings` mit Deutsch, Englisch, Franzoesisch und
  Italienisch; zentrale Keys in `L10n.swift`; sichtbare Basis-UI und Fehlermeldungen
  sind lokalisiert.
- Entscheidung: Neue sichtbare Strings muessen kuenftig in den String Catalog.

#### 20.2 Sprachumschalter in der App
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Picker in den Einstellungen mit `Nach System`, Deutsch, Englisch,
  Franzoesisch und Italienisch.
- Entscheidung: `Nach System` bleibt Default; feste Sprachen setzen die SwiftUI-Locale
  fuer Hauptfenster und Einstellungen.

#### 20.3 Lokalisierungs-QA
- Status: In Diskussion
- Prioritaet: v1
- Empfehlung: Spaeter pro Sprache Screenshots/Smoke-Test ergaenzen, damit lange Texte
  in Franzoesisch/Italienisch nicht die macOS-Layouts sprengen.

---

## Offene Produktentscheidungen

1. Reader-Modus global oder pro Artikel speichern?
2. Stern und Archiv getrennt halten oder fuer v1 nur Stern?
3. Smart Filter final: Alle, Heute, Ungelesen, Mit Stern?
4. OPML-Gruppen spaeter als Ordner oder Tags importieren?
5. CloudKit Sync-Umfang, insbesondere ob Artikel-Content synchronisiert wird.
6. Ordnerverwaltung fuer Feeds: einfache Ordnerliste oder spaeter drag-and-drop
   Hierarchie?

---

## Pflege-Regel

Diese Datei ist kein statischer Wunschzettel. Bei jeder Aenderung gilt:

1. Wenn ein Feature umgesetzt wird, Status und Prioritaet hier pruefen.
2. Wenn eine Entscheidung faellt, die Entscheidung hier festhalten.
3. Wenn ein Feature verschoben oder gestrichen wird, Begruendung kurz dokumentieren.
4. Wenn `AGENTS.md` Milestones oder "Aktuell in Arbeit" aendert, diese Datei abgleichen.
5. Vor Abschluss einer Aufgabe Tests/Build laufen lassen und die Verifikation in der Antwort nennen.
