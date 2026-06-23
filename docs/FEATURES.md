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
  dezenter Original-Link im Footer. Der Artikelkopf startet mit etwas mehr Abstand
  zur Toolbar und nutzt einen feinen Querstrich zwischen Lead-Bild und Fliesstext.
- In der Reader-Toolbar kann ein rechter Metadaten-Inspector eingeblendet werden;
  dort sind Feed-Ordner und Artikel-Tags sichtbar und bearbeitbar. Vorhandene
  globale Tags, die dem Artikel noch nicht zugewiesen sind, werden dort als
  anklickbare Plus-Chips angeboten. Der Artikelkopf zeigt Feedname, Lesezeit,
  Zeitpunkt sowie Ordner und Artikel-Tags als dezente Chips direkt unter dem Titel;
  der Inspector wird als native rechte macOS-Inspector-Spalte angezeigt,
  nutzt denselben hellen Stil wie die linke Sidebar und bleibt beim Feed- oder
  Artikelwechsel eingeblendet, wenn er geoeffnet wurde.
- Die native Artikel-Scrollbar ist ausgeblendet, damit der Artikelbereich optisch
  fliessender in die rechte Inspector-Leiste uebergeht.
- Reader-Rendering wandelt HTML/Plain-Text in Absätze und Bildbloecke; das Lead-Bild
  steht immer direkt unter dem Titel. `Article.imageURL` gewinnt, sonst wird das
  erste HTML-Bild nach vorne gezogen.
- Offline Mode Phase 1 ist umgesetzt: Feed-gelieferter `Article.content` wird in
  SwiftData gespeichert, spaeter gelieferter Volltext wird bei bestehenden Artikeln
  nachgetragen, Artikel koennen im Reader manuell offline gespeichert/entfernt
  werden, und Reader sowie Artikelliste zeigen den Offline-Status.
- ArticleRowView zeigt Titel, Datum, Summary, optionales Bild, Ungelesen-Punkt
  rechts oben und Stern rechts unten.
- Artikelbilder werden beim Feed-Parsing robuster aus Media RSS, iTunes Image,
  Bild-Enclosures und HTML-Content extrahiert; relative Bild-URLs werden zu absoluten
  URLs normalisiert. Falls ein Feed-Item kein Bild enthaelt, kann Feedivo die
  verlinkte Artikelseite pruefen und `og:image`/`twitter:image` als Artikelbild
  uebernehmen.
- Feed- und Favicon-HTML-Regulaerausdruecke werden statisch gecacht, damit
  `NSRegularExpression` nicht bei jedem Artikel, Feed-Refresh oder Favicon-Link-Tag
  neu kompiliert wird.
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
  gemeldet. Der Sammel-Refresh nutzt `withTaskGroup`, damit Netzwerkrequests fuer
  mehrere Feeds parallel laufen koennen.
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
- Das Settings-Fenster nutzt nun eine linke Kategorienavigation nach Variante A:
  Allgemein, Darstellung, Feeds, Aktualisierung, Tags & Regeln und Sync sind klar
  getrennte Bereiche statt eines langen Formulars.
- In der Artikelansicht koennen Titel- und Fliesstext-Schrift ueber kuratierte
  Presets direkt per Toolbar-Popover und in den Einstellungen getrennt gewaehlt werden;
  Fliesstext-Groesse, Titel-/Fliesstext-Zeilenabstand und Artikelbreite sind dort
  ebenfalls einstellbar. Metazeile, Ordner-Chip und Tag-Chips nutzen bewusst die
  App-Oberflaechenschrift statt der Reader-Schriftwahl.
- Automatischer Refresh ist als macOS-native Basis umgesetzt: In den Einstellungen
  kann er aktiviert und auf 15, 30, 60 oder 120 Minuten gestellt werden. Feedivo nutzt
  `NSBackgroundActivityScheduler`; macOS entscheidet den genauen Zeitpunkt und startet
  eine vollstaendig beendete App dafuer nicht neu.
- Favicons werden beim Hinzufuegen und Aktualisieren per HTML Discovery erkannt,
  in `Feed.faviconURL` gespeichert und in der Sidebar angezeigt; `/favicon.ico`
  bleibt Fallback, externe Favicon-Dienste werden nicht genutzt.
- Smart Filter sind in der Sidebar umgesetzt: Alle Artikel, Ungelesen, Mit Stern
  und Heute zeigen feeduebergreifend die passenden gespeicherten Artikel. Die
  Artikellisten nutzen dafuer gezielte SwiftData-Queries statt pauschal alle Artikel
  im Speicher zu filtern. Die Filter-Icons haben passende Farben: blau, tuerkis,
  gelb und gruen. Der Filter `Ungelesen` zeigt die Gesamtzahl aller ungelesenen
  Artikel ueber gespeicherte `Feed.unreadCount` Werte.
- Die linke Sidebar nutzt wieder einen hellen, systemnahen macOS-Look mit dezenter
  Auswahlflaeche und bestehenden farbigen Smart-Filter-Icons.
- Die Hauptbereiche der linken Sidebar (`Filter`, `Tags`, `Regeln`, `Ordner`) sind
  einklappbar und merken ihren Zustand ueber Feedwechsel und App-Neustarts.
- Artikel-Links koennen kopiert und Originalartikel im Standardbrowser geoeffnet
  werden; die Aktionen sind im Artikel-Kontextmenue, Reader und macOS-Menue `Artikel`
  verfuegbar. In der Artikelansicht oeffnet auch ein Klick auf den Titel den
  Originalartikel, sofern ein gueltiger Link vorhanden ist.
- Feed Eigenschaften sind als Basis umgesetzt: Rechtsklick auf einen Feed oeffnet
  ein lokalisiertes Sheet mit Feed-Header, Statusmetriken, Metadaten, editierbarem
  Aktualisierungsintervall, naechstem Abruf, letztem Artikel, Kopierbutton fuer die
  XML-Adresse und den neuesten 20 Feed-Log-Eintraegen. Website und XML-Adresse sind
  bei gueltigen Webadressen anklickbar.
- Vorheriger/naechster Artikel ist als Basis umgesetzt: Reader-Toolbar und
  macOS-Menue `Artikel` navigieren mit `Cmd+↑`/`Cmd+↓` innerhalb der aktuell sichtbaren
  Feed- oder Smart-Filter-Liste; am Listenrand gibt es keinen Loop.
- OPML Import/Export ist umgesetzt: Import liest `.opml`/`.xml`, ueberspringt
  Duplikate anhand der Feed-URL, uebernimmt OPML-Gruppen als `folderName` und
  aktualisiert neu importierte Feeds direkt ueber den normalen Refresh-Pfad. Die
  Anlage/Deduplizierung laeuft sequenziell, der anschliessende Refresh der neuen
  Feeds parallel per `withTaskGroup`; Export schreibt die aktuelle Feed-Liste als
  `Feedivo.opml`.
- Einfache Ordnerverwaltung ist umgesetzt: Feeds stehen in der Sidebar-Section
  `Ordner`, der Section-Titel hat einen + Button zum Erstellen neuer Ordner,
  leere Ordner werden als `FeedFolder` gespeichert, Ordner sind aufklappbar,
  Feeds in Ordnern sind eingerueckt, und der Ordnername kann in den Feed-Eigenschaften
  bearbeitet oder geleert werden.
- Zentrale Tag-Verwaltung und Sidebar-Tag-Filter sind als Basis umgesetzt: Tags
  koennen erstellt, umbenannt, gefaerbt und geloescht werden; die Sidebar zeigt Tags
  als klickbare Zeilen mit Farbindikator und Artikelzaehler und filtert die Artikelliste
  feeduebergreifend auf direkt getaggte Artikel sowie Artikel aus Feeds mit diesem
  Tag. Nach dem Erstellen wird das neue Tag direkt als Sidebar-Filter ausgewaehlt.
  Feed-Tags werden in den Feed-Eigenschaften bearbeitet; Tag-Badges zaehlen direkte
  Artikel-Tags und Feed-Tags ohne Duplikate.
- Automatische Regeln sind als Basis mit UI umgesetzt: Neue Artikel werden beim
  Feed-Refresh automatisch getaggt; Regeln koennen in den Einstellungen erstellt,
  bearbeitet, geloescht und aktiviert/deaktiviert werden. Der Wizard bietet einfache
  Regeln sowie Power-User-Regeln mit mehreren Bedingungen und AND/OR. Aktive Regeln
  koennen in den Einstellungen manuell auf vorhandene Artikel angewendet werden.
- Projekt baut und Unit-Tests laufen; UI-Test-Runner blockierte lokal am 2026-06-19
  vor dem App-Launch an einer alten Feedivo-PID.

### Aktuell in Arbeit

M4 Polish & Release:
- M1, M2 und M3 sind abgeschlossen.
- Tag-Verwaltung, Tag-Sidebar-Filter, Feed-Tags, RuleEngine, Rule-UI,
  Background-Refresh-Status und Offline-Basis sind als M3-Basis abgeschlossen.
- iCloud Sync wurde bewusst nach M4 verschoben, damit Sync zusammen mit Release-,
  Cache- und Import-Polish geplant und getestet werden kann.
- M4-Basis umgesetzt: Erweiterter OPML-Import-Dialog und Offline Mode Phase 1
  mit manuellem Speichern/Entfernen einzelner Artikel.
- Naechster Fokus: Bild-/Favicon-Cache, Offline-Automatik/Speicherverwaltung,
  Onboarding oder iCloud Sync.

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
- Bildposition: Das erste sichtbare Bild steht im nativen Reader immer direkt unter
  dem Titel. Ein gespeichertes `Article.imageURL` hat Vorrang; wenn es fehlt, wird
  das erste HTML-`img` aus dem Artikelinhalt nach vorne gezogen.
- Visueller Rhythmus: Ein feiner Trenner erscheint nach dem Lead-Bild, wenn danach
  Fliesstext folgt.
- Performance: `ReaderPreparedArticle` bereitet Content-Bloecke, Metazeile und
  Original-URL einmal pro ausgewaehltem Artikel vor, damit SwiftUI-Redraws nicht
  wiederholt HTML/Text neu zerlegen.
- Metadaten: Oberhalb des Titels zeigt `ReaderView` Feedname, ungefaehre Lesezeit
  und Artikelalter in der App-Oberflaechenschrift, sofern die Daten vorhanden sind.
- Design-Exploration: Unter `docs/design/article-reader-prototypes/index.html`
  liegen zehn interaktive Reader-Varianten als Entscheidungsgrundlage fuer die
  spaetere visuelle Ueberarbeitung der Artikelansicht.
- Reduzierte Folge-Exploration: Unter
  `docs/design/article-reader-minimal-step/index.html` liegen drei bewusst ruhige
  Varianten fuer die Positionierung von Feedname, Lesezeit, Ordner und Tags, weil
  die Schriftarten selbst bereits individuell konfigurierbar sind.
- Glass-Inspector-Exploration: Unter
  `docs/design/article-info-glass-sidebar-prototypes/index.html` liegen fuenf
  konkrete Varianten fuer eine macOS-Glass-Anpassung der rechten Artikelinfos-
  Seitenleiste.
- Umgesetzte Richtung: Der rechte Artikelinfos-Inspector nutzt SwiftUIs native
  `.inspector`-Spalte und denselben hellen, systemnahen Stil wie die linke Sidebar.
  Beim Einblenden rueckt der Reader inklusive Toolbar nach links.
- Implementierte Richtung: Feedname, Lesezeit und Zeitpunkt bleiben im Artikelkopf;
  Ordner und Tags werden unter dem Titel angezeigt und koennen im einblendbaren
  rechten Inspector bearbeitet werden.
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
- Performance: `ArticleListView` berechnet `ArticleNavigationState` aus der sichtbaren
  Liste und meldet nur vorherigen/naechsten Artikel nach oben, damit `ContentView`
  beim Feed-Wechsel nicht die komplette Artikelliste kopieren muss.
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
  neue Tags als `Tag` gespeichert. Noch nicht zugewiesene vorhandene Tags werden im
  rechten Inspector als Plus-Chips angezeigt und koennen direkt angeklickt werden.
- Implementiert: Tag-Farben, zentraler Tag-Manager und Sidebar-Tag-Filter sind als
  Basis umgesetzt. Neu erstellte Tags werden direkt in der Sidebar ausgewaehlt.
- Implementiert: Feed-Tags koennen in den Feed-Eigenschaften zugewiesen werden.
  Sidebar-Tag-Filter und Tag-Badges beruecksichtigen direkt getaggte Artikel sowie
  Artikel aus getaggten Feeds ohne Duplikate.

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

#### 1.12 Offline Mode
- Status: Fertig als Phase 1
- Prioritaet: M4/v1
- Implementiert: Feed-gelieferter Volltext/HTML-Content wird als `Article.content`
  in SwiftData gespeichert und vom nativen Reader vor der Summary genutzt.
- Implementiert: Wenn ein bestehender Artikel beim spaeteren Refresh erstmals
  Volltext vom Feed liefert, wird fehlender lokaler `Article.content` nachgetragen;
  vorhandener Content wird nicht durch leere Feed-Werte ersetzt.
- Implementiert: Wenn nur eine Summary offline vorhanden ist, zeigt der native Reader
  einen dezenten Hinweis und verweist auf `Original oeffnen` fuer den vollstaendigen
  Artikel.
- Implementiert: Artikel koennen im Reader manuell offline gespeichert oder wieder
  entfernt werden. Bestehender Feed-Content wird direkt als Offline-Kopie markiert;
  fehlt Feed-Content, laedt `OfflineDownloadService` die Original-URL und speichert
  den geladenen HTML/Text in `Article.offlineContent`.
- Implementiert: `Article.offlineStateRaw`, `offlineContent`, `offlineRequestedAt`,
  `offlineSavedAt` und `offlineErrorMessage` halten den Offline-Zustand pro Artikel
  nachvollziehbar fest. Reader und Artikelliste zeigen verfuegbar/fehlgeschlagen
  sichtbar an.
- Bewusst nicht in Phase 1: Automatisches Herunterladen, Readability-Extraktion,
  Bild-/Favicon-Cache, Speicherlimit und Cache-Aufraeumen. Diese Punkte bleiben
  wegen Paywalls, Cookie-Bannern, kaputtem HTML, Performance, Speicher und
  Quellen-Unterschieden eigene M4-Folgepunkte.
- Abgrenzung: Bilddaten bleiben nicht in SwiftData; lokaler Bild- und Favicon-Cache
  ist als M4-Thema separat geplant.

### 2. Artikel-Liste

#### 2.1 Artikel anzeigen
- Status: Fertig
- Prioritaet: MVP
- Implementiert: `ArticleRowView` mit Titel, Datum, Summary, Statuspunkt, Stern und
  optionalem Bild.
- Performance: Feed-Listen und Smart-Filter-Listen fragen ihre jeweilige Teilmenge
  direkt per SwiftData-Predicate ab. Feed-Listen nutzen nicht mehr die komplette
  `Feed.articles` Relationship, sondern eine Query auf `Article.feedID`.
- Performance: `ArticleListView` reagiert direkt auf `.onChange(of: articles)` und
  erzeugt kein separates UUID-Array mehr bei jedem SwiftUI-Renderdurchlauf.
- Bildbasis: `FeedService` speichert absolute `Article.imageURL` Werte aus Media RSS,
  iTunes Image, Bild-Enclosures, JSON Feed Bildern oder HTML-`img` Quellen.
- Performance: Metabilder der verlinkten Artikelseite (`og:image`/`twitter:image`)
  werden nicht mehr automatisch bei jedem `fetchFeed` geladen. `FeedViewModel` ruft
  die explizite Artikelbild-Anreicherung nur fuer neue Artikel ohne Feed-Bild und
  fuer bereits gespeicherte, noch bildlose Artikel auf.

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
  RSS-Systemsymbol. Feed-Zeilen zeigen rechts eine dezente Badge mit der Anzahl
  ungelesener Artikel, sobald der Feed ungelesene Artikel enthaelt.
- Performance: Die Badges basieren auf `Feed.unreadCount`; die Sidebar muss dafuer
  weder alle ungelesenen Artikel materialisieren noch Feed-Relationships zaehlen.
- Migration: `FeedUnreadCountBackfillService` korrigiert vorhandene Zaehler einmalig
  und merkt den erfolgreichen Durchlauf per `feedUnreadCountBackfillDone_v1`, damit
  nicht bei jedem App-Start alle Feed-Artikel geladen werden.
- Design: Helle, systemnahe linke Sidebar; aktive Zeilen werden dezent ueber die
  Accent-Farbe markiert, damit die linke Spalte ruhig bleibt.
- Ordner: Feeds stehen in der Section `Ordner`; Feeds mit `folderName` werden unter
  einem Ordnerkopf gruppiert, Feeds ohne Ordner bleiben direkt in dieser Section.
  Neben dem Section-Titel erstellt ein + Button neue leere Ordner. Feeds innerhalb
  eines Ordners werden eingerueckt angezeigt; Ordner sind per Chevron auf- und
  zuklappbar.
- Offen: Drag & Drop fuer Ordner.

#### 3.2 Smart Filter
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Sidebar-Filter fuer Alle Artikel, Ungelesen, Mit Stern und Heute.
  Die Artikelliste nutzt dafuer gespeicherte Artikel ueber passende SwiftData-Queries
  statt nur einen Feed oder pauschal alle Artikel im Speicher.
  Die Filter-Icons sind farbig und passen semantisch zum jeweiligen Symbol. Der
  Filter `Ungelesen` zeigt rechts die feeduebergreifende Anzahl ungelesener Artikel.
- Entscheidung: Die bestehenden SF-Symbol-Icons bleiben im hellen Sidebar-Design
  erhalten; Hintergrund und Auswahlstil folgen wieder naeher dem macOS-Standard.
- Entscheidung: Erweiterte/eigene Smart Filter wurden fuer M3 geprueft und bewusst
  zurueckgestellt. Die M3-Basis bleibt bei Alle Artikel, Ungelesen, Mit Stern und Heute.
- Spaeter: Eigene Smart Filter, weitere Zeitfilter wie Gestern und eventuell
  gespeicherte Filterregeln erst nach Suche/Filter-Polish erneut planen.

#### 3.3 Tag-Abschnitt
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Die Sidebar zeigt vorhandene Tags unterhalb der Smart Filter als
  klickbare Zeilen mit Farbindikator. Ein Klick filtert die mittlere Artikelliste
  feeduebergreifend auf direkt getaggte Artikel und Artikel aus getaggten Feeds.
- Implementiert: Tag-Zeilen zeigen eine dezente Artikelanzahl-Badge; direkte
  Artikel-Tags und Feed-Tags werden ohne Duplikate gezaehlt. Tags ohne Artikel
  bleiben ohne Badge.

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
  zuletzt aktualisiert und die neuesten 20 Feed-Log-Eintraege. Website und XML-Adresse
  sind anklickbar, wenn sie gueltige `http`/`https`-URLs sind.
- Log: Feed hinzufuegen, erfolgreiche Aktualisierung und Refresh-Fehler werden in
  SwiftData als `FeedLogEntry` gespeichert; pro Feed bleiben die neuesten 20 Eintraege.
- Ordner: Der Ordnername wird direkt im Sheet bearbeitet; leere Eingaben entfernen
  den Ordner vom Feed.

#### 4.3 Feed loeschen
- Status: Fertig als Basis
- Prioritaet: MVP
- Implementiert: Rechtsklick auf Feed in der Sidebar und macOS-Menue `Feed` mit
  deaktivierter Aktion ohne Auswahl.
- Implementiert: In den Einstellungen gibt es im Bereich `Feeds` eine
  Feed-Verwaltung mit Suche, Mehrfachauswahl, `Alle sichtbaren auswählen`,
  `Auswahl aufheben` und destruktiver Loeschbestaetigung fuer mehrere Feeds.
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
- Implementiert: Bei `Alle Feeds aktualisieren` und beim Aktualisieren neu
  importierter OPML-Feeds zeigt Feedivo ein kompaktes Fortschritts-Overlay mit
  Zaehler und Fortschrittsbalken.

#### 4.5 Automatischer Refresh
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Globaler automatischer Refresh ueber `NSBackgroundActivityScheduler`
  mit Einstellung fuer Ein/Aus und Intervalle 15, 30, 60 oder 120 Minuten.
- Verhalten: Nutzt denselben Refresh-Pfad wie `Alle Feeds aktualisieren`; einzelne
  Feed-Fehler stoppen den Gesamtlauf nicht.
- Implementiert: Feedivo speichert den letzten automatischen Refresh-Zeitpunkt,
  den Status, eine optionale letzte Fehlermeldung und den naechsten geschaetzten
  automatischen Lauf. Die Einstellungen zeigen diese Werte kompakt unter dem
  Auto-Refresh-Schalter.
- Einschraenkung: macOS bestimmt den exakten Ausfuehrungszeitpunkt. Vollstaendig
  beendete Apps werden fuer diese Basis nicht neu gestartet, weil `BGTaskScheduler`
  fuer native macOS Apps nicht verfuegbar ist.

### 5. Tags und Regeln

#### 5.1 Tags verwalten
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Artikel-Tags koennen im Reader-Inspector hinzugefuegt und entfernt
  werden. Tags koennen zentral erstellt, umbenannt, farblich markiert und geloescht
  werden. Die Sidebar kann nach Artikeln mit einem ausgewaehlten Tag filtern; neue
  Tags werden nach dem Erstellen direkt als Sidebar-Filter ausgewaehlt. Sidebar-
  Tag-Zeilen zeigen die Anzahl passender Artikel.
- Implementiert: Feed-Tags koennen in den Feed-Eigenschaften zugewiesen und entfernt
  werden; Sidebar-Tag-Filter und Tag-Badges schliessen Artikel aus getaggten Feeds
  ein.
- Implementiert: Neue Artikel koennen beim Refresh ueber einfache Regeln automatisch
  getaggt werden.

#### 5.2 Automatische Regeln
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: `RuleEngine` wertet Regeln fuer neue Artikel beim Feed-Refresh aus.
  Unterstuetzte Felder sind `title`, `summary` und `feedTitle`; unterstuetzte
  Operatoren sind `contains`, `startsWith` und `endsWith`.
- Implementiert: Regeln koennen in den Einstellungen erstellt, geoeffnet, bearbeitet,
  geloescht und aktiviert/deaktiviert werden.
- Implementiert: Der Regel-Wizard unterstuetzt einfache Regeln mit einer Bedingung
  sowie Power-User-Regeln mit mehreren Bedingungen und AND/OR-Verknuepfung.
- Implementiert: Der Regel-Wizard zeigt eine Live-Vorschau, wie viele vorhandene
  Artikel die aktuelle Bedingungskombination treffen wuerde, ohne Tags zu setzen.
- Implementiert: Die Sidebar zeigt Regeln nur kompakt mit aktivem Zaehler und bietet
  `Regel aus Artikel erstellen...` fuer den aktuell ausgewaehlten Artikel an.
- Implementiert: In den Einstellungen koennen aktive Regeln manuell auf vorhandene
  Artikel angewendet werden; bestehende Tag-Zuweisungen werden nicht dupliziert und
  die Anzahl neu gesetzter Tags wird angezeigt.
- Verhalten: Deaktivierte Regeln, leere Suchwerte, unbekannte Felder/Operatoren und
  Regeln ohne Ziel-Tag werden ignoriert. Tags werden nicht doppelt zugewiesen.
- Offen: Regex, Ausblenden und andere Aktionen.

### 6. iCloud Sync

#### 6.1 CloudKit Sync
- Status: In Diskussion
- Prioritaet: M4/v1
- Empfehlung: Erst aktivieren, wenn Datenmodell und Grundfeatures stabil sind.
- Entscheidung: Am 2026-06-22 bewusst von M3 nach M4 verschoben.
- Sync-Umfang: Feeds, gelesen, Stern, Tags, Regeln. Artikel-Content ist nun als
  Offline-Basis gespeichert und muss wegen Speicher/CloudKit-Volumen bewusst
  geprueft werden.

### 7. OPML

#### 7.1 OPML Import
- Status: Fertig als Basis
- Prioritaet: MVP
- Umsetzung: macOS-Dateiimport fuer `.opml`/`.xml`; Duplikate werden anhand der
  normalisierten Feed-URL uebersprungen. Neue Feeds werden direkt nach dem Import
  ueber den normalen Refresh-Pfad aktualisiert; nach der sequenziellen Anlage laeuft
  dieser Refresh parallel per `withTaskGroup`.
- Hinweis: OPML-Gruppen werden als `Feed.folderName` gespeichert und dadurch direkt
  in der Sidebar gruppiert.

#### 7.2 Erweiterter OPML-Import-Dialog
- Status: Fertig als M4-Basis
- Prioritaet: M4/v1
- Ziel: Vor dem Import soll Feedivo die ausgelesenen Feeds und OPML-Ordner anzeigen,
  damit der Benutzer den Import prüfen und gezielt anpassen kann.
- Umsetzung: Liste der erkannten Feeds mit Titel, Feed-URL, Website falls vorhanden,
  Duplikat-Hinweis und aktueller/aus OPML gelesener Ordnerzuordnung.
- Umsetzung: Ordnerzuordnung pro Feed im Dialog ändern; vorhandene Ordner auswählen
  und neue Ordner direkt im Import-Dialog erstellen.
- Umsetzung: Option, ob neu importierte Feeds direkt aktualisiert werden sollen. Wenn
  deaktiviert, werden nur Feeds und Ordner importiert; das ist schneller und der
  Refresh kann spaeter manuell erfolgen.
- Umsetzung: Nach dem Import eine Zusammenfassung anzeigen, z.B. importierte Feeds,
  übersprungene Duplikate, angelegte Ordner, Refresh aktiviert/deaktiviert und
  fehlgeschlagene Aktualisierungen.
- Design-Exploration: Unter `docs/design/opml-import-dialog-prototypes/index.html`
  liegen fuenf interaktive Varianten: Review Table, Guided Wizard, Split Inspector,
  Batch Editor und Import Center.
- Entscheidung: Variante A / Review Table ist die bevorzugte Umsetzungsrichtung.
  Die OPML-Datei soll im selben Dialog ausgewaehlt oder gewechselt werden; danach
  erscheinen Preview, Ordnerbearbeitung, Refresh-Option und Import-Zusammenfassung
  ohne zweiten separaten Dialog.
- Umsetzung: Die OPML-Datei kann per Button ausgewaehlt oder direkt auf das
  Importfenster gezogen werden. Drag & Drop akzeptiert `.opml` und `.xml` und nutzt
  denselben Preview-Pfad wie die Datei-Auswahl.
- Entscheidung: Die Preview soll aus der wirklich ausgewaehlten OPML-Datei erzeugt
  werden. Importiert werden nur ausgewaehlte importierbare Feeds; Duplikate und
  nicht erreichbare/problematische Feeds bleiben in der Liste sichtbar und werden
  klar markiert.
- Option: Im Import-Dialog kann der Benutzer bewusst erlauben, dass Duplikate
  ebenfalls importiert werden. Standard bleibt, Duplikate zu ueberspringen.
- Option: Nicht erreichbare oder problematische Feeds koennen ebenfalls bewusst
  importiert werden. Standard bleibt, diese Feeds sichtbar zu markieren, aber nicht
  auszuwaehlen.
- UI-Regel: Auch bei vielen Feeds bleibt das Dialogfenster stabil gross; die
  Feed-Tabelle scrollt intern. Lange Feednamen und URLs werden einzeilig mit
  Ellipsis gekuerzt.
- UI-Regel: Die echte SwiftUI-Umsetzung orientiert sich visuell an Variante A des
  Prototyps: Header mit Status-Badge, Datei-Kachel, Review-Table mit festen Spalten,
  kompakte Status-Pills und Footer-Optionen im selben Dialog.
- UI-Regel: Die Review-Tabelle hat ein Status-Dropdown fuer alle, neue, doppelte
  oder nicht erreichbare Feeds. Der Filter darf die Import-Zeilen nicht neu erzeugen;
  Auswahl- und Ordner-Aenderungen bleiben erhalten, wenn der Filter geloescht wird.
- UI-Regel: Waehrend Feedivo die Preview vorbereitet, steht der Ladezustand mittig
  in der spaeteren Feed-Tabelle und nennt den konkreten Prueffortschritt, damit
  bei groesseren OPML-Dateien klar sichtbar ist, dass weiter gearbeitet wird.
- Hinweis: Die bestehende OPML-Service-Basis bleibt erhalten; erweitert wird vor
  allem der Import-Workflow und die UI rund um Preview, Auswahl und Ergebnis.
  Der alte direkte Dateiimport wurde durch `OPMLImportReviewView` ersetzt.

#### 7.3 OPML Export
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

### 20. Bild- und Favicon-Cache

#### 20.1 Lokaler Bildcache
- Status: Entschieden
- Prioritaet: M4/v1
- Ziel: Artikelbilder und Favicons sollen nach dem ersten Laden lokal verfuegbar
  bleiben, damit Feedivo sie beim App-Start, Feedwechsel und Scrollen nicht immer
  erneut aus dem Netz laden muss.
- Empfehlung: Eigener `ImageCacheService` mit Disk-Cache im macOS-Cache- oder
  Application-Support-Verzeichnis plus kleinem `NSCache` im Speicher. Die Views
  nutzen spaeter eine gemeinsame `CachedImageView` statt direktem `AsyncImage`.
- Umfang: Artikelbilder in Liste und Reader sowie Favicons in Sidebar, Feed-
  Eigenschaften und Umbenennen-Sheet.
- Entscheidung: Bilddaten nicht in SwiftData speichern. SwiftData bleibt fuer
  URLs, Artikel, Tags, Regeln und Feed-Metadaten; grosse Bild-BLOBs wuerden die
  Datenbank und spaeter CloudKit unnoetig belasten.
- Spaeter: Einstellung zum Cache-Leeren und optionales Cache-Limit, z.B. 500 MB.

### 21. Mehrsprachigkeit

#### 21.1 i18n Foundation
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: `Localizable.xcstrings` mit Deutsch, Englisch, Franzoesisch und
  Italienisch; zentrale Keys in `L10n.swift`; sichtbare Basis-UI und Fehlermeldungen
  sind lokalisiert.
- Entscheidung: Neue sichtbare Strings muessen kuenftig in den String Catalog.

#### 21.2 Sprachumschalter in der App
- Status: Fertig als Basis
- Prioritaet: v1
- Implementiert: Picker in den Einstellungen mit `Nach System`, Deutsch, Englisch,
  Franzoesisch und Italienisch.
- Entscheidung: `Nach System` bleibt Default; feste Sprachen setzen die SwiftUI-Locale
  fuer Hauptfenster und Einstellungen.

#### 21.3 Lokalisierungs-QA
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
