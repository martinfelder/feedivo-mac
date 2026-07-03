# Feedivo macOS — Feature Liste
> **Für Codex:** Diese Datei ist die massgebliche Quelle für alle Features.
> Implementiere nur Features mit Status ✅ Entschieden oder 🔨 In Arbeit.
> Features mit 💬 In Diskussion noch NICHT implementieren — warten auf Entscheid.
> Features mit ⏸️ Zurückgestellt kommen nach v1.
>
> Status-Legende:
> ✔️ Fertig | 🔨 In Arbeit (teilweise umgesetzt) | ✅ Entschieden (bereit zur Implementierung) | 💬 In Diskussion | ⏸️ Zurückgestellt
>
> Zuletzt aktualisiert: 2026-07-03

---

## 1. Reader

### 1.1 Anzeigemodus
- **Status:** ✔️ Fertig
- **Umgesetzt:** Beide Modi implementiert — nativer SwiftUI Text-Renderer + `WebContentView` (NSViewRepresentable-Wrapper für WKWebView)

### 1.2 Navigation (Vor / Zurück)
- **Status:** ✔️ Fertig
- **Umgesetzt:** `ArticleNavigationState`, Toolbar-Buttons, `Cmd+↑` / `Cmd+↓`

### 1.3 Gelesen / Ungelesen markieren
- **Status:** ✔️ Fertig
- **Umgesetzt:** `ArticleViewModel.toggleRead`, `markReadIfNeeded`, `Cmd+Shift+U`

### 1.4 Stern / Favoriten
- **Status:** ✔️ Fertig
- **Umgesetzt:** `ArticleViewModel.toggleStarred`, `Cmd+D`, Smart Filter "Mit Stern"

### 1.5 Tag manuell zuweisen
- **Status:** ✔️ Fertig
- **Umgesetzt:** `ArticleMetadataInspectorView` — Toggle-Pills, neue Tags direkt erstellbar

### 1.6 Artikel teilen
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Teilen via macOS Share Sheet — ausgelöst aus Kontextmenü (Feature 2.4)
  - Kein separater Teilen-Button im Reader
  - Geteilt wird: Titel + URL des Artikels
- **Hinweis:** Export via Share Sheet ist nicht dasselbe wie Artikel-Link teilen
  und bleibt ein späterer Export-Slice.

### 1.7 Im Browser öffnen
- **Status:** ✔️ Fertig
- **Umgesetzt:** `Original öffnen` im Inspector, nutzt Standard-Browser

### 1.8 Reader-Ansicht (Vollartikel-Extraktion)
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Dritter Modus im Reader (neben nativem SwiftUI Text und WKWebView)
  - Toggle in der Reader-Toolbar zum Wechseln zwischen den 3 Modi
  - Technisch: Readability.js via WKWebView (Option A — Mozilla Standard)
  - Extraktion startet automatisch, sobald der User den Modus `Vollartikel` auswählt
  - Braucht Internet-Verbindung — lädt Originalseite und extrahiert Hauptinhalt
  - Kein zusätzlicher Bestätigungsbutton vor dem Laden
  - Wenn der Vollartikel nicht geladen werden kann, zeigt Feedivo einen Hinweis,
    dass der Anbieter dies nicht zulässt und diese Vorgabe zu respektieren ist
  - Entscheidung: extrahierter Vollartikel wird temporär im Reader angezeigt und
    nicht als Artikel-/Offline-Content gespeichert

### 1.9 Schriftgrösse / Font anpassen
- **Status:** ✔️ Fertig
- **Umgesetzt:** `ReaderFontPreset` (18 Presets), `ReaderTypography`
- **Robustheit:** Gebündelte Custom-Fonts werden beim App-Start und beim
  tatsächlichen Erzeugen der Reader-Schrift registriert; Presets wählen einen
  aktuell verfügbaren PostScript-Namen statt blind den ersten Kandidaten.

### 1.10 Link in Zwischenablage kopieren
- **Status:** ✔️ Fertig
- **Umgesetzt:** Inspector + `Cmd+L`

### 1.11 Regel erstellen aus Artikel
- **Status:** ✔️ Fertig
- **Umgesetzt:** `RuleWizardView` vorausgefüllt aus Artikel-Kontext
- **SQLite/GRDB 2026-07-03:** Der Menüpunkt im produktiven `SQLiteReaderView`
  ist wieder aktiv verdrahtet und öffnet den SQLite-first `RuleWizardView` über
  `ContentView`.

---

## 2. Artikel-Liste

### 2.1 Artikel anzeigen
- **Status:** ✔️ Fertig
- **Umgesetzt:** `ArticleRowView`, `ArticleListView` mit SwiftData-Query

### 2.2 Sortierung GUI
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Toolbar-Menü in der Artikel-Liste als primärer Weg
  - Menüleiste `Darstellung → Sortieren nach`
  - Sortieroptionen: Neueste zuerst (Standard) / Älteste zuerst / Nach Feed / Nach Titel A-Z / Nach Lesezeit kurze zuerst
  - Sortierung gilt global, wird per `@AppStorage` gespeichert und von allen Artikellisten genutzt
  - `ArticleSortOption` kapselt Sortierlogik und Labels testbar

### 2.3 Filterung GUI
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Smart Filter in Sidebar vorhanden
  - Filter-Icon mit Dropdown in der Toolbar der Artikel-Liste (Schnellzugriff)
  - Filter-Optionen: Alle / Ungelesen / Mit Stern / Archiviert / Heute
  - Filter gilt global, gespeichert via `@AppStorage`
  - Sidebar bleibt primärer Weg

### 2.4 Kontextmenü
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  1. Als gelesen markieren / Als ungelesen markieren
  2. Stern setzen / Stern entfernen
  3. Archivieren / Aus Archiv entfernen
  4. Tag zuweisen... (Tag-Liste als Untermenü)
  5. Regel erstellen... (RuleWizard vorausgefüllt; zusätzlich im Menü der Artikelansicht)
  6. Im Browser öffnen
  7. Link kopieren
  8. Teilen... (macOS Share Sheet)
  9. Offline speichern / Offline-Kopie entfernen
  10. Artikel löschen
  11. Exportieren... öffnet den Artikel-Exportdialog aus Feature 18.1a
  12. ─────────────────
  13. Alle als gelesen markieren (gilt für aktuell sichtbare Liste)
- **Hinweis:** Das normale `Teilen...` nutzt das macOS Share Sheet für Artikel-
  Links. Datei-Teilen für vorbereitete Exporte läuft im Exportdialog; Batch-
  Export bleibt ein späterer Export-Slice.

### 2.5 Artikel-Liste Anzeige-Logik
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Ungelesene Artikel: immer angezeigt, unabhängig vom Alter
  - Gelesene Artikel: standardmäßig ausgeblendet in der Liste
  - Am Ende der Liste: Button "X gelesene Artikel anzeigen" — Klick blendet alle gelesenen Artikel ein
  - Filtermenü bietet zusätzlich "Gelesene ausblenden" und "Gelesene und ungelesene anzeigen"
  - Artikel, die durch "beim Öffnen als gelesen markieren" automatisch gelesen werden, bleiben bis zum Feed-/Listenwechsel sichtbar
  - Gelesene Artikel bleiben verfügbar bis automatisches Löschen greift (Standard 90 Tage)
  - Der aktuell ausgewählte Artikel bleibt sichtbar, wenn er beim Öffnen automatisch als gelesen markiert wird
  - Toolbar-Menü `Als gelesen markieren` markiert nur Artikel der aktuell angezeigten Liste
    als gelesen: aktueller Feed oder aktueller intelligenter Ordner. Optionen:
    `Älter als ein Tag`, `Älter als zwei Tage`, `Älter als drei Tage`,
    `Älter als vier Tage`, `Älter als eine Woche`, `Älter als zwei Wochen` und
    `Alle sichtbaren Artikel`.

---

## 3. Sidebar

### 3.1 Feed-Liste
- **Status:** ✔️ Fertig
- **Umgesetzt:** `SidebarView`, `FeedRowView`, `FeedFolderOrganizer`, `SidebarUnreadCount`

### 3.2 Smart Filter
- **Status:** ↪️ Ersetzt durch Intelligente Ordner
- **Entscheidung:** Die festen Smart Filter werden nicht weiter ausgebaut. Alle
  Standardansichten laufen künftig als vordefinierte Intelligente Ordner.
- **Abgedeckt durch Intelligente Ordner:** Alle Artikel, Ungelesen, Mit Stern,
  Heute, Ausgeblendet, Archiviert, Diese Woche und Gespeichert.

### 3.3 Tag-Abschnitt
- **Status:** ✔️ Fertig
- **Umgesetzt:** Eigene Section, feedübergreifende Filterung

---

## 4. Feed-Verwaltung

### 4.1 Feed hinzufügen — Website Feed-Suche
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - `FeedDiscoveryService` erkennt direkte Feed-URLs und normale Website-URLs
  - Bei Website-URL wird HTML nach `<link rel="alternate">` Feeds für RSS, Atom und JSON Feed durchsucht
  - Relative Feed-URLs werden gegen die Website-URL aufgelöst und Duplikate entfernt
  - Ein gefundener Feed wird im `AddFeedSheet` direkt vorausgewählt
  - Mehrere gefundene Feeds werden als vollständige Auswahlliste angezeigt
  - Kein Feed gefunden → klare Fehlermeldung
  - Im SQLite/GRDB-Hauptpfad legt `SQLiteFeedSubscriptionService` neue Feeds
    SQLite-first an. SwiftData speichert dabei nur noch eine minimale Feed-
    Übergangsidentität für Sidebar/ContentView; neue Artikel aus diesem Flow
    liegen in SQLite.
- **Entscheidung:** Die Suche startet per Button `Suchen`, nicht automatisch beim Tippen, damit keine unnötigen Netzwerkabrufe pro Tastendruck entstehen.

### 4.2 Feed bearbeiten
- **Status:** ✔️ Fertig
- **Umgesetzt:** `FeedPropertiesView`, `FeedRenameView`

### 4.3 Feed löschen
- **Status:** ✔️ Fertig
- **Umgesetzt:** `FeedViewModel.deleteFeed`, Bestätigungsdialog

### 4.4 Manueller Refresh
- **Status:** ✔️ Fertig
- **Umgesetzt:** `refreshFeed` / `refreshAllFeeds`, Fortschritt im unteren Statusbereich
- **Performance:** Der Refresh erkennt bestehende Artikel über einen gezielten
  `Article.feedID`-Fetch statt über die vollständige `feed.articles`-Relationship.
  Der Lookup lädt keine schweren Artikeltexte, und unveränderte bestehende
  Artikelwerte werden nicht erneut geschrieben. Sammel-Refreshes aus der UI laufen
  über `FeedBackgroundRefreshService` mit eigenen SwiftData-Kontexten pro Feed:
  `FeedViewModel` erstellt nur leichte Feed-Snapshots, hält Progress/Status auf
  dem MainActor und übernimmt am Ende grobe Ergebnis- und Benachrichtigungsdaten.
  Der laufende Fortschritt vermeidet globale Animationen, und Feed-Batches setzen
  ihre Live-Status gesammelt auf `refreshing`. Zusätzlich speichert Feedivo pro
  Feed HTTP-Validatoren (`ETag`, `Last-Modified`, Body-Hash) und nutzt sie für
  Conditional GET. Unveränderte Feeds werden bei HTTP 304 oder gleichem Body-Hash
  ohne FeedKit-Parsing, Artikel-Lookup, Bildanreicherung und Regelverarbeitung
  abgeschlossen. Für unveränderte Feeds wird kein neuer Info-Logeintrag
  geschrieben, damit große Sammel-Refreshes keine reinen “0 neue Artikel”-Logs
  massenhaft in SwiftData einfügen. Wenn gespeicherte Validatoren und HTTP-Status
  bereits identisch sind, bleibt das `Feed`-Objekt unverändert und es wird kein
  SwiftData-Save ausgelöst.

### 4.5 Automatischer Refresh
- **Status:** ✔️ Fertig
- **Umgesetzt:** `NSBackgroundActivityScheduler`, 15/30/60/120 Min.

### 4.6 Refresh-Status im unteren Statusbereich
- **Status:** ✔️ Fertig
- **Umgesetzt:** Während `Alle Feeds aktualisieren` läuft, erscheint unten rechts
  neben dem Online-/Offline-Status ein kompakter Fortschrittsstatus mit
  aktualisierten Feeds von Gesamtzahl und einem Chevron zum Aufklappen. Das
  Detailpanel zeigt live jeden Feed als wartend, aktualisierend, erfolgreich
  (grünes Checkmark) oder fehlgeschlagen (rotes X). Nach fehlerfreiem Abschluss
  bleibt die Summary 2 Minuten sichtbar; bei Teilfehlern bleibt sie stehen, bis
  der User sie schließt oder der nächste Sammel-Refresh startet. Der laufende
  Status bleibt auch bei sehr schnellen Refreshes mindestens kurz sichtbar.
  Details bleiben weiterhin in Feed-Logs und bestehender Fehlermeldung.

### 4.7 Feeds beim App-Start aktualisieren
- **Status:** ✔️ Fertig
- **Umgesetzt:** In den Einstellungen → Aktualisierung gibt es die Option
  `Feeds beim Start aktualisieren` (Standard aus). Wenn aktiv, startet Feedivo
  nach dem Öffnen des Hauptfensters einmalig einen Sammel-Refresh aller Feeds und
  nutzt dieselbe aufklappbare Fortschrittsanzeige aus 4.6. Der periodische
  Background-Refresh teilt sich dasselbe `FeedViewModel`, damit automatische
  Refreshes im laufenden Hauptfenster ebenfalls sichtbar werden.

---

## 5. Tags & Regeln

### 5.1 Tags erstellen und verwalten
- **Status:** ✔️ Fertig
- **Umgesetzt:** `TagManagerView`, `TagViewModel`, Farbauswahl

### 5.2 Automatische Regeln — Settings-Design
- **Status:** ✔️ Fertig
- **Umgesetzt:** `RuleEngine`, `RuleWizardView`, Live-Vorschau, rückwirkend anwendbar
- **Umgesetzt — Regelliste in Einstellungen:**
  - Jede Regel als Zeile: Toggle (aktiv/inaktiv) — Name — Bedingung zusammengefasst — Aktion als Pill
  - Reihenfolge per Hoch-/Runter-Buttons änderbar; Regeln werden von oben nach unten ausgewertet
  - Echtes Drag & Drop für die Reihenfolge
  - Doppelklick öffnet RuleWizard zum Bearbeiten
  - Rechtsklick: Bearbeiten / Duplizieren / Löschen
  - `+` Button für neue Regel
  - "Alle Regeln jetzt anwenden" Button (rückwirkend auf bestehende Artikel)
  - Anzahl betroffener Artikel pro Regel anzeigen
  - Regex als Operator mit kurzer Hilfe direkt im RuleWizard
- **Regel-Aktionen:**
  - Tag zuweisen (bereits vorhanden)
  - Benachrichtigung auslösen (neu — siehe Feature 10.2)
  - Artikel ausblenden (umgesetzt — siehe Feature 16.3)

---

## 6. iCloud Sync

### 6.1 Sync via CloudKit
- **Status:** ⏸️ Zurückgestellt — zugunsten SQLite/GRDB-Performance-Umbau
- **Entscheidung 2026-07-02:** Die SwiftData/CloudKit-Beta wird pausiert, weil
  Feedivo für große Datenmengen zuerst eine lokale SQLite-only-Architektur mit
  GRDB bekommt. Performance hat Vorrang vor Sync.
- **Frühere Vorarbeit:** CloudKit-Schema-Blocker durch nicht-optionale
  SwiftData-Relationships ist behoben; syncbare Beziehungen bleiben optional und
  werden im bestehenden SwiftData-Code nil-sicher gelesen.
- **Neu zu planen:** Ein späterer Sync muss auf der SQLite/GRDB-Architektur
  aufsetzen oder als bewusst getrennte zweite Schicht neu entworfen werden.

---

## 7. OPML

### 7.1 OPML Import
- **Status:** ✔️ Fertig
- **Umgesetzt:** `OPMLImportReviewView`, zweiphasiger Import, Drag & Drop,
  Übernahme des gewählten bzw. gespeicherten Aktualisierungsintervalls für neu
  importierte Feeds
- **SQLite/GRDB 2026-07-03:** OPML-Import und First-Run-Wizard nutzen dieselbe
  SQLite-first Subscription-Logik wie Feed hinzufügen. Neue Feeds und neue
  Artikel aus Add-/Import-Flows liegen in SQLite; SwiftData hält nur die
  temporäre Feed-Übergangsidentität. Doppelte OPML-Feed-URLs werden über
  Service-Logik gesteuert, deshalb ist `feeds.url` bewusst nicht mehr unique.
- **Refactor (2026-06-27):** Der OPML-Preview-Flow wurde aus Review-View und
  First-Run-Wizard in einen gemeinsamen `OPMLImportPreviewController` plus
  einheitlicher `OPMLImportFeedRow` extrahiert, sodass Wizard und Settings-Import
  dieselbe Vorschau-/Auswahl-/Ordnerlogik nutzen. Controller-Logik ist über
  `OPMLImportPreviewControllerTests` testbar abgesichert.

### 7.2 OPML Export
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Wiederverwendbarer `OPMLExportSheet` nach freigegebenem Product-Design-Prototyp.
  - Auslösen via Menüleiste `Feed → OPML exportieren...` und Einstellungen → Feeds.
  - Export-Optionen:
    - Feed-URLs + Titel immer aktiv und nicht deaktivierbar.
    - Ordner-Struktur als OPML-Gruppen optional.
    - Tags optional als `category`-Attribut.
    - Feed-Beschreibung optional als `description`-Attribut.
  - Live-Zusammenfassung im Dialog mit Feed-, Ordner-, Tag- und Beschreibungsanzahl.
  - Standard-Dateiname: `Feedivo-Export-YYYY-MM-DD.opml`.
  - Favorisierte Artikel werden bewusst nicht im OPML exportiert; das bleibt Sache von Feature 18.

---

## 8. Einstellungen

### 8.1 Bestehendes Settings-Fenster
- **Status:** ✔️ Ersetzt
- **Umgesetzt:** Die frühere Sidebar-/Form-Fassung wurde durch die neue
  Toolbar-Oberfläche ersetzt.
- **Entscheidung 2026-06-29:** Die alten Settings können weg, weil alle Inhalte
  in die neue Oberfläche migriert sind. Es gibt kein separates
  `Einstellungen alt`-Fenster und kein zusätzliches Settings-Menü mehr.

### 8.2 Settings-Toolbar
- **Status:** ✔️ Fertig
- **Umgesetzt:** Einziges Settings-Fenster mit macOS-artiger Icon-Toolbar.
  Bereiche: Allgemein, Anzeige, Feeds, Ordner, Offline-Lesen,
  Benachrichtigungen, Aktualisierung, Bereinigung, Regeln, Sync und Über.
- **Umgesetzt — Feeds:** Die Feedliste zeigt pro Feed neben Titel und URL auch
  die Anzahl veröffentlichter Artikel der letzten 7 Tage und den Zeitpunkt der
  letzten Aktualisierung.
- **Bewusst:** Die Oberfläche nutzt die echten Settings-Bindings und
  Verwaltungsviews; es gibt keinen Parallelbetrieb mit der alten Fassung mehr.
- **Entscheidung 2026-06-29:** Die neue Oberfläche bleibt die echte
  SwiftUI-`Settings`-Scene. Der systemeigene macOS-Einstellungen-Eintrag öffnet
  direkt diese Oberfläche.
- **Entscheidung 2026-06-30:** Das Einstellungen-Fenster ist in dieser Form
  übernommen und gilt für v1 als ausreichend final.
- **Design-Ziel:** Kompakte macOS-Settings-Skalierung nach Referenzscreen:
  breites Fenster für Toolbar und Verwaltungsbereiche, aber kleinere
  Toolbar-Kacheln, kleine Controls, enge Zeilenabstände und screenshot-nahe
  Typografie statt groß skaliertem Formular-Look.

---

## 9. Suche

### 9.1 Volltext-Suche
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Die Artikelliste zeigt ein einzelnes kompaktes Suchfeld.
  - Die Suche filtert nur die bereits geladenen Artikel der aktuell ausgewählten
    Liste: aktueller Feed, Tag, Smart Filter oder intelligenter Ordner.
  - Suchbereich in der Liste ist bewusst einfach: Alles, also Titel,
    Zusammenfassung und Inhalt.
  - Bestehende Sortierung, bestehender Filter und die Logik für gelesene sowie
    ausgeblendete Artikel bleiben erhalten.

### 9.2 Suchfilter
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - `Cmd+F` öffnet ein separates Suchfenster mit eigener Ergebnisliste.
  - Das Suchfenster durchsucht alle gespeicherten Artikel.
  - Suchbereiche: Alles, Titel, Zusammenfassung und Inhalt.
  - Filteroptionen in der Suche: Feed, Tag, Zeitraum und Status.
  - Zeitraum: jederzeit, heute, diese Woche.
  - Status: alle, ungelesen, gelesen, mit Stern, archiviert.
  - Filter funktionieren auch ohne Suchtext und lassen sich mit Suchtext und
    Suchbereich kombinieren.
  - Im SQLite/GRDB-Hauptpfad lädt das Suchfenster keine globale SwiftData-
    Artikelliste mehr, sondern leichte `ArticleListSnapshot`s direkt aus
    `ArticleStore.searchArticles(state:)`.

### 9.3 Spotlight-Integration
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Artikel als Core Spotlight Items indexieren via `CSSearchableItem`
  - Klick auf Spotlight-Resultat öffnet Feedivo direkt beim Artikel (Deep Link)
  - Einstellungen → Suche: Toggle "Artikel in Spotlight indexieren" (an/aus)

---

## 10. Benachrichtigungen

### 10.1 Feed-Benachrichtigungen
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Toggle "Benachrichtigung" pro Feed in Feed-Eigenschaften (`FeedPropertiesView`)
  - `Feed.isNotificationEnabled` als SwiftData-Feld mit sicherem Default `false`
  - Zusammenfassung pro Refresh über `FeedNotificationService`, z.B. `5 neue Artikel` mit Feed-Liste `Heise, Mac & i`
  - `refreshFeed` und `refreshAllFeeds` melden neue Artikel nach erfolgreichem Speichern an den Notification-Service
  - Einstellungen zeigen den macOS-Erlaubnisstatus und können die Benachrichtigungs-Erlaubnis anfragen
  - Klick auf Benachrichtigung öffnet Feedivo; präzise Feed-Navigation folgt mit Deep-Linking/Command-Routing (Feature 23.2)
- **Bewusst später:**
  - Benachrichtigungen aus einer vollständig beendeten App heraus bleiben abhängig von der bestehenden macOS-Refresh-Basis und werden erst nach weiterem Background-Testing final bewertet.

### 10.2 Regelbasierte Benachrichtigungen
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - `Benachrichtigung auslösen` als Regel-Aktion im RuleWizard neben `Tag zuweisen` und `Artikel ausblenden`
  - Benachrichtigungs-Text pro Regel mit Platzhaltern `{Titel}`, `{Feed}` und `{Regel}`
  - Priorität pro Regel: Normal / Kritisch; Kritisch wird aktuell als zeitkritische lokale macOS-Benachrichtigung vorbereitet
  - `RuleEngine.applyRulesWithNotifications` liefert Regel-Treffer zurück, ohne die bestehende Tag-/Ausblenden-Logik zu brechen
  - `refreshFeed` und `refreshAllFeeds` sammeln Regel-Treffer für neue Artikel und melden sie an `FeedNotificationService`
  - Zusammenfassung wenn mehrere Artikel dieselbe Regel auslösen, z.B. `3 neue Apple-Artikel`
  - Unabhängig von Feed-Benachrichtigungen (10.1); rückwirkendes Anwenden bestehender Regeln löst keine macOS-Benachrichtigungen aus

### 10.3 Benachrichtigungs-Einstellungen
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Badge-Zähler auf App-Icon — Anzahl ungelesener Artikel
  - Einstellungs-Kategorie "Benachrichtigungen" im Settings-Fenster
  - Toggle `Badge-Zähler am App-Icon anzeigen`
  - Badge wird bei App-Start, geänderten Feed-Zählern und beim Umschalten der Einstellung aktualisiert
- **Noch offen (nicht jetzt):**
  - Stille Stunden
  - Benachrichtigungen auf iPhone/iPad (abhängig von iCloud Sync — Feature 6.1)

---

## 11. Lesedauer-Schätzung

### 11.1 Lesedauer pro Artikel
- **Status:** ✔️ Fertig
- **Umgesetzt:** Lesezeit-Berechnung in `ReaderMetadataFormatter` vorhanden und im Reader sichtbar
- **Entscheidung 2026-06-29:** Die Lesedauer wird bewusst nicht in der Artikel-Liste
  angezeigt, weil sie dort für den User nicht relevant genug ist. Die Artikel-Liste
  soll kompakt bleiben und wichtige Scanning-Signale priorisieren.

### 11.2 Lesefortschritt
- **Status:** ⏸️ Zurückgestellt
- **Entscheidung 2026-07-01:** Der erste Ansatz mit Fortschrittsbalken, gespeicherter Scrollposition und Scrollbeobachtung im Reader wurde entfernt, weil er das Scrollgefühl verschlechtert hat.
- **Empfehlung:** Für v1 ohne Lesefortschritt bleiben. Ein späterer Versuch sollte erst mit einem performanten, isolierten Reader-Scroll-Konzept prototypisiert werden.

---

## 12. Feed hinzufügen (erweitert)

### 12.1 Website Feed-Suche
- **Status:** ✅ Entschieden — siehe Feature 4.1

### 12.2 Feed-Suche (Discover)
- **Status:** ⏸️ Zurückgestellt
- **Grund:** Feedly API kostenpflichtig — nach v1 evaluieren. In v1 reicht URL/Website-Erkennung (Feature 4.1)

### 12.4 Feed-Vorschau vor dem Abonnieren
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Vorschau nach URL-Eingabe: Titel, Icon und letzte 5 Artikel anzeigen
  - Vorschau erscheint im gleichen Sheet wie URL-Eingabe (kein separater Schritt)
  - User bestätigt mit `Abonnieren` oder bricht ab
  - Mehrere gefundene Feeds bleiben auswählbar; die Vorschau wechselt mit der Auswahl

---

## 13. Feed-Metadaten

### 13.1 Feed-Infos anzeigen
- **Status:** ✔️ Fertig
- **Umgesetzt:** `FeedPropertiesView`, `FeedPropertiesFormatter`
- **Umgesetzt 2026-06-29:** `Feed Eigenschaften...` enthält eine eigene Section
  `Aktivität` mit Artikelanzahl der letzten 7 Tage und letzter Aktualisierung.

### 13.2 Feed-Gesundheit
- **Status:** ✔️ Fertig
- **Umgesetzt:** `FeedLogEntry`, Log der letzten 20 Abrufe

---

## 14. Statistiken

### 14.1 Lese-Statistiken
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Separates Fenster — auslösbar via Menüleiste oder `Cmd+Shift+S`
  - Statistiken:
    - Artikel gelesen heute / diese Woche / gesamt
    - Meistgelesene Feeds (Top 5)
    - Aktivste Lesetage (Heatmap à la GitHub)
    - Durchschnittliche Lesezeit pro Tag
    - Meistgenutzte Tags
  - Zeitraum wählbar: 7 Tage / 30 Tage / Gesamt

### 14.2 Feed-Statistiken
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - In `FeedPropertiesView` integrieren (bestehende Feed-Info-Ansicht)
  - Artikel pro Woche (Durchschnitt)
  - Lese-Prozentsatz (wie viel % der Artikel werden gelesen)
  - Durchschnittliche Lesedauer für diesen Feed

### 14.3 Statistik-Daten exportieren
- **Status:** 💬 In Diskussion — noch nicht implementieren

---

## 15. Feeds organisieren (Ordner)

### 15.1 Ordner erstellen und verwalten
- **Status:** ✔️ Fertig
- **Umgesetzt:** `FeedFolder`, `FeedFolderOrganizer`

### 15.2 Feeds per Drag & Drop organisieren
- **Status:** ⏸️ Zurückgestellt
- **Grund:** Hoher Aufwand — nach v1

### 15.3 OPML-Gruppen als Ordner
- **Status:** ✔️ Fertig

---

## 16. Intelligente Ordner

### 16.1 Intelligenter Ordner
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Eigener Abschnitt "Intelligente Ordner" ganz oben in der Sidebar
  - Dynamische Ansicht — befüllt sich automatisch nach Bedingungen
  - Verfügbare Bedingungen:
    - Tag ist X
    - Feed ist Y / Feed ist in Ordner Z
    - Datum (heute / diese Woche / älter als X Tage)
    - Status (ungelesen / mit Stern / archiviert / ausgeblendet)
    - Titel enthält Text
    - Text im Artikel enthält (Volltext-Suche)
    - Autor ist / enthält
  - UND / ODER Verknüpfung zwischen Bedingungen als globale Auswahl pro Ordner
  - Vordefinierte Intelligente Ordner erstellen: "Alle Artikel", "Ungelesen",
    "Mit Stern", "Heute", "Ausgeblendet", "Archiviert", "Diese Woche", "Gespeichert"
  - Ein Intelligenter Ordner ohne Bedingungen bedeutet "Alle Artikel"
  - Vordefinierte Ordner speichern Icon und Farbe wie normale intelligente Ordner
  - `Ungelesen` verhält sich beim automatischen Gelesen-Markieren wie Feed-Listen:
    der gerade gelesene Artikel bleibt bis zum Listenwechsel sichtbar.
  - `Mit Stern`, `Ausgeblendet` und `Gespeichert` zeigen Sidebar-Badges und
    Artikellisten mit allen passenden Artikeln, also gelesenen und ungelesenen
    Treffern.
  - V1-Entscheidung: Gemischte Operatoren oder Bedingungsgruppen werden bewusst noch nicht umgesetzt.

### 16.2 Intelligenten Ordner erstellen/bearbeiten
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Sheet ähnlich macOS Smart Mailboxes (Mail.app)
  - Name des Ordners oben
  - UND / ODER Auswahl: "Erfülle alle / eine der folgenden Bedingungen"
  - Bedingungszeilen mit + / − Buttons
  - Live-Vorschau der Resultate direkt im Sheet
  - Intelligente Ordner: umbenennbar, löschbar, duplizierbar (Rechtsklick in Sidebar)
  - Verwaltung in den Einstellungen im Stil der Regelverwaltung: Liste mit Reihenfolge,
    Sidebar-Sichtbarkeit, Trefferanzahl, Bearbeiten, Duplizieren, Löschen und Defaults wiederherstellen
  - Reihenfolge per Hamburger-Handle und Live-Drag-&-Drop; die ganze Zeile rutscht
    während des Ziehens sichtbar an die neue Position, Pfeilbuttons werden bewusst nicht verwendet
  - Beim Erstellen/Bearbeiten können Icon und Farbe gewählt werden; Sidebar und Settings nutzen diese Darstellung
  - Grafischer Prototyp: `docs/design/smart-folders-prototype/index.html`

### 16.3 Artikel ausblenden via Regel
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - "Artikel ausblenden" als Regel-Aktion im RuleWizard neben "Tag zuweisen"
  - Ausgeblendete Artikel erscheinen nicht in normalen Feed-/Tag-/Smart-Filter-Listen
  - Smart Filter "Ausgeblendet" in der Sidebar zeigt ausgeblendete Artikel
  - Rückwirkendes Anwenden läuft über den bestehenden Button "Auf vorhandene Artikel anwenden"
  - Manuelles Einblenden einzelner Artikel bleibt bewusst nicht in v1

---

## 17. Artikel archivieren

### 17.1 Offline speichern (manuell + automatisch)
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - `OfflineDownloadService`, `Article.offlineContent`, manuell via Kontextmenü
  - Einstellungen → Offline-Lesen: Toggle "Artikel mit Stern automatisch offline speichern"
  - Wenn der Toggle aktiv ist, stoßen Stern-Aktionen aus Artikelzeile,
    Inspector und Menü/Shortcut automatisch `OfflineDownloadService.saveForOffline`
    an
  - Entfernen des Sterns löscht die Offline-Kopie bewusst nicht automatisch; dafür
    bleibt die explizite Offline-Entfernen-Aktion zuständig
  - Neue Einstellungen → Allgemein → Cache zeigt Anzahl und Speichergrösse der
    bewusst offline gespeicherten Artikelinhalte und bietet
    `Offline-Kopien löschen`. Gezählt wird `Article.offlineContent`; Bilder bleiben
    Teil des gemeinsamen Bild-/Favicon-Caches.

### 17.2 Artikel-Zustände
- **Status:** ✅ Entschieden — siehe Feature 22.1

### 17.3 Automatisches Löschen
- **Status:** ✅ Umgesetzt
- **Umgesetzt:**
  - Globale Einstellung: Artikel nach X Tagen löschen, Standardwert 90 Tage
  - Standardmäßig deaktiviert, damit Feedivo nie ungefragt Artikel entfernt
  - Manueller Button "Jetzt bereinigen" in Einstellungen → Bereinigung
  - App-Start und Einstellungsänderung führen die Bereinigung aus, wenn aktiv
  - Ausnahmen: Archivierte Artikel und Artikel mit Stern bleiben standardmäßig
    erhalten
  - Option in derselben Einstellung: Auch Artikel mit Stern und archivierte Artikel
    können bewusst mitgelöscht werden
  - Pro Feed in `Feed Eigenschaften...` überschreibbar: Feed kann global erben,
    eigene Aufbewahrung aktivieren/deaktivieren, eigene Tage wählen, eine
    Mindestanzahl neuester Artikel behalten und Stern/Archivartikel optional
    mitlöschen
  - Ungelesen-Zähler betroffener Feeds werden nach dem Löschen korrigiert
  - Der Feed-Refresh importiert abgelaufene Feed-Einträge bei aktiver Aufbewahrung
    nicht erneut, damit gelöschte alte Artikel nicht wieder als ungelesen
    auftauchen
- **Hinweis 2026-06-29:** Die neue Settings-Toolbar trennt die Artikel-
  Aufbewahrung in den eigenen Bereich `Bereinigung`; die Regelverwaltung liegt
  separat unter `Regeln`.

### 17.3a Bereinigung — History, Zeitplan und Hinweis
- **Status:** ⏸️ Zurückgestellt — späterer Ausbau, nicht jetzt implementieren
- **Geplant:**
  - History der letzten 10 Bereinigungen im Bereich `Bereinigung`
  - Pro History-Eintrag: Zeitpunkt der Ausführung und Anzahl gelöschter Artikel
  - Konfigurierbarer Zeitpunkt für automatische Bereinigung:
    - bestimmter Wochentag und Uhrzeit
    - beim Starten der App
    - beim Beenden der App
  - Wenn eine Bereinigung ausgeführt wird, soll Feedivo einen sichtbaren Hinweis
    auf dem Bildschirm anzeigen, inklusive Ergebnis beziehungsweise gelöschter
    Artikelanzahl.
- **Offene Umsetzungsdetails:**
  - Persistenzmodell für die letzten 10 Läufe festlegen (`@AppStorage` reicht
    eventuell für kompakte History, SwiftData wäre robuster).
  - Klären, ob der Bildschirmhinweis als Toast/Overlay im Hauptfenster oder als
    macOS-Benachrichtigung plus In-App-Hinweis erscheinen soll.

### 17.4 Artikel-Liste Anzeige-Logik
- **Status:** ✅ Entschieden — siehe Feature 2.5

---

## 18. Artikel exportieren

### 18.1 Einzelnen Artikel exportieren
- **Status:** 🔨 Markdown/Text/HTML inkl. Offline-Bilder umgesetzt / PDF und DOCX zurückgestellt
- **Umgesetzt 18.1a:**
  - Einzelartikel-Export über Artikel-Kontextmenü, Reader-Toolbar und macOS-Menü
    `Artikel`.
  - Zweistufiger Export-Dialog nach Product-Design-Variante B: Format wählen,
    Metadaten-Option setzen, dann Vorschau prüfen und `Sichern...`.
  - Formate: Markdown (`.md`), Plain Text (`.txt`) und HTML (`.html`).
  - Markdown und HTML werden in der Vorschau gerendert; Plain Text bleibt als
    monospaced Textvorschau sichtbar.
  - Optional einschließbare Metadaten: Titel, Autor, Veröffentlichungsdatum,
    Feed-Name, URL und Tags.
  - Export bevorzugt gespeicherten Offline-Inhalt, fällt sonst auf Feed-Inhalt
    oder Summary zurück.
- **Umgesetzt 18.1b: Offline-Bilder für Markdown/HTML-Export**
  - Bei Markdown und HTML gibt es eine Option, Bilder offline einzuschließen.
  - Der Export erzeugt dafür ein ZIP-Paket mit der Artikeldatei im Root und dem
    festen Unterordner `Pictures/` für Bilder.
  - Bildpfade in der Markdown- oder HTML-Datei werden relativ auf diesen
    Unterordner umgeschrieben, damit der Export ohne Online-Zugang funktioniert.
  - Die Vorschau bettet bereits geladene Bilder temporär als `data:`-URLs ein,
    damit Markdown- und HTML-Vorschau trotz relativer Exportpfade Bilder anzeigen.
  - Fehlende Bilder blockieren den Export nicht; die Vorschau-Zusammenfassung zeigt,
    wie viele Bilder gespeichert wurden und wie viele nicht geladen werden konnten.
  - Der Dialog zeigt während der Vorbereitung Statusmeldungen für Dokument,
    Bild-Download, ZIP-Erstellung und Öffnen des Speichern-Dialogs.
  - ZIP und Text laufen über denselben stabilen FileDocument-Exportpfad; dadurch
    vermeidet der Dialog konkurrierende `.fileExporter` Präsentationen.
- **Zurückgestellt 18.1c: PDF und DOCX**
  - PDF (`.pdf`) und Word-Dokument (`.docx`) werden vorerst nicht mehr im
    Exportdialog angeboten.
  - Grund: PDF-Layout und DOCX-Ausgabe brauchen einen eigenen späteren Slice mit
    klarerem Layout-Anspruch statt weiterem Polish im aktuellen Exportdialog.
  - Entscheidung vom 2026-06-26: PDF und DOCX bleiben auf Weiteres
    zurückgestellt.
- **Umgesetzt 18.1d: Datei teilen**
  - Im Vorschau-Schritt kann die vorbereitete Exportdatei über `Teilen...` an das
    macOS Share Sheet übergeben werden.
- **Später:** PDF, DOCX, Batch-Export und ggf. reichere DOCX-Layouts bleiben
  eigene Slices.

### 18.2 Mehrere Artikel exportieren (Batch)
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Mehrfachauswahl in der Artikel-Liste via `Cmd+Klick`
  - Export-Dialog mit Ausgabe-Wahl: ein Dokument pro Artikel (ZIP) oder alles in eine Datei
  - Gilt für alle Formate aus Feature 18.1

### 18.3 Drittanbieter-Integration
- **Status:** ⏸️ Zurückgestellt
- **Grund:** In v1 reicht macOS Share Sheet — direkte Integrationen (Readwise, Obsidian, Pocket) nach v1

---

## 19. Oberflächen-Anpassung (Customization)

### 19.1 Artikel-Liste anpassen
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren (Einstellungen → Darstellung):**
  - Feeds ohne ungelesene Artikel in der Seitenleiste anzeigen / ausblenden — umgesetzt
  - Vorschautext-Zeilen: 0–3 (Stepper), Standard: 2 — 0 = nur Titel + Datum
  - Vorschaubilder in der Liste: anzeigen / ausblenden
  - Vorschaubild-Position: Links oder Rechts
  - Summary anzeigen / ausblenden
- **Noch offen (nicht jetzt) — jetzt auch entschieden:**
  - Datum-Format: User wählt in Einstellungen (relativ "vor 2 Stunden" oder absolut "23.06.2026")
  - Feed-Name pro Artikel: anzeigen / ausblenden in Einstellungen (nützlich in "Alle" / Smart Filter)
  - Ungelesen-Markierung: fetter Text + farbiger Punkt (beides zusammen)

### 19.2 Sidebar anpassen
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Ungelesen-Zähler pro Feed: anzeigen / ausblenden
  - Favicons: anzeigen / ausblenden
- **Noch offen (nicht jetzt):**
  - Sidebar-Sections komplett ausblenden

### 19.3 Reader anpassen
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Maximale Textbreite: umgesetzt als stufenloser Regler
  - Titel und Artikeltext separat fett darstellen: umgesetzt in Reader-Popover und Einstellungen → Darstellung
  - Artikelbild im Reader: anzeigen / ausblenden (separat von Vorschaubildern)
- **Nicht umsetzen:** Hintergrundbild / Sepia-Modus

### 19.4 Toolbar anpassen
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - macOS-Standard `Symbolleiste anpassen...` via Rechtsklick auf Toolbar
  - User kann Items frei hinzufügen / entfernen / umsortieren

### 19.5 Allgemeines Verhalten
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Artikel beim Öffnen automatisch als gelesen markieren: an/aus
  - Externe Links: Im Standard-Browser oder in Feedivo WebView
  - Vorschaubilder in Liste laden: an/aus (separat von Reader-Bildern)
  - Bilder im Reader laden: an/aus
- **Noch offen (nicht jetzt) — jetzt auch entschieden:**
  - Beim App-Start: letzten Feed öffnen (Standard) — wählbar in Einstellungen (letzter Feed / Alle-Ansicht)
  - Beim Vor/Zurück navigieren: folgt der globalen Einstellung "Artikel beim Öffnen automatisch als gelesen markieren" — keine separate Einstellung

### 19.6 Wo
- Alle Customization-Optionen im Einstellungen-Fenster unter "Darstellung" (bestehend erweitern)

---

## 20. Fehler- und Problembehandlung

### 20.1 Fehler-UX Konzept
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Feed nicht erreichbar: Fehler-Badge (⚠️) beim Feed in der Sidebar UND Inline-Meldung in der Artikel-Liste mit "Erneut versuchen" Button
  - Netzwerk offline: Globaler Banner oben in der App
  - Download-Fehler: Inline-Meldung mit Retry-Option
  - Fehler-Log bleibt in Feed-Eigenschaften (bereits vorhanden)

### 20.2 Leere Zustände (Empty States)
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Erster Start ohne Feeds: First-Run-Wizard auslösen (bereits vorhanden)
  - Feed hat keine Artikel: Erklärung + "Feed aktualisieren" Button
  - Suche ohne Resultate: Hinweis mit Suchbegriff und Vorschlag Suchbereich zu erweitern
  - Tag ohne Artikel: Hinweis dass noch keine Artikel diesen Tag haben

---

## 21. Menubar-App

### 21.1 Menubar-Icon
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Menubar-Icon mit Dropdown (neueste X Artikel + "Feedivo öffnen" Button)
  - Anzahl Artikel im Dropdown: konfigurierbar in Einstellungen
  - Schnellaktionen im Dropdown: Refresh, Alle als gelesen markieren
  - Badge-Zähler auf Menubar-Icon: Anzahl ungelesener Artikel
  - App ohne Dock-Icon betreibbar: Einstellung in Einstellungen (LSUIElement)
  - Klick auf Artikel im Dropdown: In Feedivo öffnen oder im Browser — konfigurierbar

---

## 22. Artikel-Zustände

### 22.1 Explizite Artikel-Zustände
- **Status:** ✔️ Fertig
- **Umgesetzt — 4 kombinierbare Zustände:**
  - `isRead: Bool` — gelesen/ungelesen (bereits vorhanden)
  - `isStarred: Bool` — Favorit/Stern (bereits vorhanden)
  - `isArchived: Bool` — Archivstatus, mit expliziter Offline-Kopie verknüpft
  - `isHidden: Bool` — versteckte Artikel werden aus normalen Listen ausgeblendet
- **Kombinierbar:** Alle 4 Zustände sind unabhängig und kombinierbar
- **Archivieren:** Speichert eine Offline-Kopie und setzt `isArchived` nur, wenn Offline-Content verfügbar ist
- **Archivierte Artikel löschen:** `removeArchive` entfernt `isArchived` + lokalen Offline-Inhalt, Artikel bleibt in Liste
- **Technisch:** `OfflineDownloadService` verknüpft Archivstatus mit `offlineContent`; Entfernen von Offline-Content löscht auch den Archivstatus
- **Abgrenzung:** Regel-Aktion "Ausblenden" und Smart Filter "Ausgeblendet" bleiben Feature 16.3/3.2

---

## 23. Share Extension / Deep Links

### 23.1 Share Extension (empfangen)
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - "In Feedivo öffnen" im macOS Share Sheet anderer Apps (Safari, Browser etc.)
  - Feed-URL aus beliebiger App direkt in Feedivo abonnieren
  - Artikel-URL aus beliebiger App in Feedivo öffnen zum Lesen

### 23.2 URL-Schema (Deep Links)
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - `feedivo://add?url=https://...` — Feed direkt hinzufügen
  - `feedivo://article?id=...` — direkt zu einem Artikel springen
  - Nützlich für macOS Shortcuts, Raycast, Alfred, Automator
  - URL-Schema in `Info.plist` registrieren

---

## 24. Mehrfenster-Unterstützung

### 24.1 Mehrere Fenster
- **Status:** ✔️ Fertig
- **Umgesetzt:**
  - Artikel in separatem Artikelfenster öffnen via `Cmd+Return` und Kontextmenü
  - Kein zweites Hauptfenster: Das neue Fenster zeigt den Reader für genau einen
    Artikel
  - Rechte Artikel-Seitenleiste/Inspector kann eingeblendet werden, damit Feed,
    Ordner, Tags, Lesestatus, Stern, Archiv/Offline und Quelle direkt bearbeitet
    werden können
  - Vorheriger/nächster Artikel funktioniert auch im Artikelfenster
  - Wenn derselbe Artikel bereits in einem Artikelfenster geöffnet ist, wird dieses
    Fenster fokussiert statt ein Duplikat zu öffnen
  - Fenster-Zustand beim Beenden speichern und beim Start optional wiederherstellen
  - Einstellung unter `Allgemein`: `Artikelfenster beim Start wiederherstellen`
    mit Standard **aus**
  - `WindowGroup` in SwiftUI für die Artikelfenster nutzen

---

## 25. Drucken

### 25.1 Artikel drucken
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - `Cmd+P` druckt den aktuellen Artikel
  - Im Druckdialog wählt der User: Reader-Darstellung oder Original-Webseite
  - Metadaten (Datum, Feed-Name, URL) im Druckbild optional

---

## 26. Barrierefreiheit & Qualität

### 26.1 Barrierefreiheit (Accessibility)
- **Status:** ⏸️ Zurückgestellt
- **Grund:** Nach v1 — VoiceOver und Reduce Motion werden später berücksichtigt

### 26.2 Performance bei vielen Feeds
- **Status:** 🔨 In Arbeit — Qualitätsziel für Codex
- **Ziel:** 500 Feeds / 100'000 Artikel flüssig
- **Architekturentscheidung 2026-07-02:** Feedivo übernimmt für den
  Performance-kritischen Hauptpfad grundsätzlich NetNewsWires Mechanik:
  SQLite-only mit GRDB, getrennte Tabellen für Artikel und Artikelstatus,
  gezielte SQL-Snapshots für Sidebar/Liste/Reader und Statusänderungen nur über
  `article_statuses`. Die erste Welle umfasst Feeds, Refresh, Artikelliste,
  Reader, Status und Feed-Logs; weitere Nutzerpfade wie Tags, Regeln, Smart
  Folders, OPML, Export, Offline-Download und FTS-Suche werden danach einzeln
  an SQLite angeschlossen. Seit 2026-07-03 existieren auch SQLite-
  Verwaltungstabellen und Stores für Feed-Ordner, Regeln und Smart Folders;
  vorhandene SwiftData-Verwaltungsdaten werden beim App-Start nach SQLite
  gespiegelt. iCloud Sync und SwiftData-Bestandsdatenmigration bleiben bewusst
  zurückgestellt. Spec:
  `docs/superpowers/specs/2026-07-02-sqlite-grdb-performance-architecture-design.md`.
- **Umgesetzt:**
  - SQLite/GRDB-Fundament angelegt: GRDB Package, `FeedivoDatabase`, v1-
    Migrationen für `feeds`, `articles`, `article_statuses` und `feed_logs`,
    Record-Typen, erste Stores für Feeds/Artikel/Status/Timeline und Tests gegen
    temporäre In-Memory-Datenbanken.
  - SQLite-Refresh-Kern angelegt: `SQLiteFeedRefreshService` ruft einen
    injizierbaren Fetcher auf, schreibt Artikel per Batch-Upsert in einer
    SQLite-Transaktion, erzeugt/erhält getrennte Statuszeilen, aktualisiert
    `feeds.unreadCount`, HTTP-Validatoren und `feed_logs`.
  - Normaler Feed-Lese-Pfad als SQLite-Scheibe verdrahtet: `FeedivoApp` öffnet
    die GRDB-Datenbank aus Application Support, `ContentView` hält eine separate
    SQLite-Artikel-Auswahl, `SQLiteFeedArticleListView` lädt Feed-Timelines über
    `TimelineStore`, `SQLiteReaderView` lädt Reader-Snapshots über `ArticleStore`
    und Statusaktionen schreiben direkt in `article_statuses`. Spec:
    `docs/superpowers/specs/2026-07-02-sqlite-feed-reader-path-design.md`.
  - Artikel-Datenbank-Fassade ergänzt: `ArticleDatabase` bündelt `FeedStore`,
    `TimelineStore`, `ArticleStore` und `ArticleStatusStore` für den produktiven
    Listen-/Reader-Pfad. `SQLiteFeedArticleListState` und `SQLiteReaderState`
    koordinieren Artikel-Timelines, Reader-Snapshots und Statusänderungen damit
    über eine gemeinsame SQLite-Fassade statt über mehrere direkte Store-Zugriffe.
  - `ArticleDatabase` 2026-07-03 NetNewsWire-artiger verbreitert: Die Fassade
    bietet allgemeine Fetch-Methoden für einen Feed, mehrere Feeds, Artikel-IDs,
    ungelesene/heutige/markierte Artikel, Suche und aggregierte `ArticleCounts`.
    Neue Artikelpfade sollen bevorzugt diese API nutzen, damit UI/ViewModels
    nicht erneut direkt an einzelne SQLite-Stores koppeln.
  - SQLite-Timeline-Fetch-Mechanik abgeschlossen: `SQLiteFeedArticleListState`
    startet Timeline-Loads nun über eine kleine NetNewsWire-artige
    Queue/Operation-Schicht. Laufende und wartende Loads werden bei Feed-, Tag-,
    SmartFilter-, SmartFolder- oder Suchwechsel gecancelt; während ein Load noch
    läuft, bleibt nur der neueste Pending-Request erhalten. Damit können schnelle
    Feedwechsel keine alten oder mittleren Artikel-Snapshots mehr in die aktuelle
    Liste schreiben.
  - Normale Feed-Aktionen befüllen den neuen SQLite-Pfad: `AddFeedSheet`,
    ausgewählter Feed-Refresh und `Alle Feeds aktualisieren` übergeben die
    geöffnete `FeedivoDatabase` an `FeedViewModel`. Hinzufügen und einzelner
    Refresh spiegeln Feed- und Artikelsnapshots nach SQLite.
    `refreshAllFeeds(..., modelContainer:, sqliteDatabase:)` läuft inzwischen
    SQLite-first über `SQLiteFeedRefreshService` und ruft Feeds nicht mehr erst
    über SwiftData und danach ein zweites Mal fürs SQLite-Mirroring ab. Feed-
    Refresh-Benachrichtigungen werden in diesem Pfad wieder mit aktualisiertem
    Feed-Titel und dem leichten `isNotificationEnabled`-Snapshot gemeldet;
    `hideArticle`- und `notify`-Regeln laufen für neue SQLite-Artikel über
    sendbare Regel-/Artikelsnapshots. `assignTag`-Regeln schreiben inzwischen
    über `TagStore` in `tags` und `article_tags`; Sidebar-Tag-Badges für direkte
    Artikel-Tags lesen Counts inzwischen aus `TagStore.sidebarTags()`.
    Tag-Filter laden Artikel über `TimelineScope.tag` aus SQLite und umfassen
    direkte Artikel-Tags sowie Feed-Tags aus `feed_tags`. Vorhandene SwiftData-
    Feed-Tags werden beim App-Start per `FeedTagBackfillService` nach SQLite
    nachgezogen. Der Tag-Manager spiegelt Create, Rename, Farbänderungen und
    Delete nach SQLite; die Sidebar-Tag-Liste liest inzwischen
    `TagSidebarSnapshot`s aus SQLite.
  - Sidebar-Feed-Zeilen lesen Anzeige-Snapshots aus SQLite: `SQLiteSidebarState`
    lädt `FeedSidebarSnapshot` über `FeedStore`, `FeedRowView` bevorzugt daraus
    Titel, Favicon und ungelesene Counts. Auswahl, Kontextmenüs,
    Feed-Eigenschaften spiegeln Feed-Tag-Änderungen nach SQLite; Tag-Manager-
    Mutationen schreiben ebenfalls nach SQLite. Smart-Folder-Badges lesen
    `unread`, `starred`, `hidden` und `saved` aus dem SQLite-
    `SmartFolderSidebarBadgeSnapshot`, statt eine SwiftData-Artikel-Query in der
    Sidebar zu halten. Die Feed-Eigenschaften laden die sichtbare Feed-Log-Liste
    und Log-Anzahl inzwischen über `FeedLogStore` aus SQLite-`feed_logs`.
    `Neuester Artikel` und `Artikel der letzten 7 Tage` kommen ebenfalls aus
    SQLite über `ArticleStore.feedPropertiesMetrics` und
    `FeedPropertiesArticleMetricsSnapshot`; auch die Feed-Verwaltungszeilen in
    den Einstellungen nutzen diese leichte GRDB-Metrik statt SwiftData-
    Artikelqueries.
    Vordefinierte globale SmartFilter wie `Alle Artikel`, `Ungelesen`,
    `Mit Stern`, `Heute` und `Ausgeblendet` laden ihre Artikellisten ebenfalls
    über `TimelineScope.smartFilter` aus SQLite. Das SQLite-FTS-Fundament ist
    mit `article_search`, Triggern auf `articles` und
    `ArticleStore.searchArticles` umgesetzt. Die normale Suchleiste der
    `SQLiteFeedArticleListView` nutzt inzwischen denselben FTS-Index über
    `TimelineStore` und kombiniert Suchtext mit Feed-, Tag- und SmartFilter-
    Scopes. Das separate globale Suchfenster nutzt ebenfalls SQLite/FTS über
    `ArticleStore.searchArticles(state:)` und hält keine globale SwiftData-
    Artikel-Query mehr.
  - Benutzerdefinierte intelligente Ordner laden ihre Artikellisten ebenfalls
    aus SQLite. `SQLiteSmartFolderSnapshot` übersetzt Definitionen in sendbare
    Bedingungen, `TimelineScope.smartFolder` baut daraus SQL für Tags, Feed,
    Feed-Ordner, Datum, Status, Titel, Autor und Text, wobei `text contains` den
    vorhandenen FTS-Index nutzt. `ContentView` routet ausgewählte Smart Folders
    nun auf `SQLiteFeedArticleListView` und den SQLite-Reader-Pfad.
    `SmartFolderSettingsView`, `SmartFolderEditorView` und Sidebar-
    Kontextaktionen verwalten die Definitionen inzwischen direkt über
    `SQLiteSmartFolderStore`; Settings-Trefferzahlen und Editor-Preview zählen
    über `TimelineStore.count(scope: .smartFolder(...))`.
  - SQLite-Verwaltungsdefinitionen 2026-07-03 ergänzt: Migration v6 legt
    `feed_folders`, `rules`, `rule_conditions`, `smart_folders` und
    `smart_folder_conditions` an. `FeedFolderStore`, `SQLiteRuleStore` und
    `SQLiteSmartFolderStore` bieten GRDB-CRUD und erzeugen Snapshots für
    RuleEngine/Sidebar. `SQLiteAdminDefinitionBackfillService` spiegelt
    bestehende SwiftData-Verwaltungsdaten beim App-Start nach SQLite.
    TagManager, Sidebar-Feed-Ordner, Smart-Folder-Verwaltung sowie
    RuleSettings/RuleWizard laufen inzwischen SQLite-first; SwiftData bleibt
    dafür nur noch Übergangs-/Backfill-Quelle.
  - Feed-Verwaltung 2026-07-03 SQLite-first gemacht: Migration v7 ergänzt
    Feed-Admin-Felder in `feeds`; `FeedRenameView`, `FeedPropertiesView` und die
    Feed-Verwaltung in den Einstellungen laden und mutieren `FeedRecord`s über
    `FeedStore`. Feed-Tags in den Feed-Eigenschaften laufen über `TagStore` und
    `feed_tags`; der OPML-Export aus der Feed-Verwaltung nutzt SQLite-
    `OPMLFeed`-Snapshots.
  - Feed hinzufügen, OPML-Import und First-Run-Wizard legen neue Feeds inzwischen
    SQLite-first über `SQLiteFeedSubscriptionService` an. SwiftData speichert
    dabei nur noch eine minimale Feed-Übergangsidentität für Sidebar/ContentView
    bis zum finalen FeedRecord-Umbau; neue Artikel aus Add-/Import-Flows liegen
    in SQLite. Doppelte OPML-Feed-URLs werden in der Service-Logik entschieden,
    `feeds.url` ist daher bewusst nicht mehr unique.
  - SQLite-Statusänderungen halten Feed-Zähler aktuell: `ArticleStatusStore`
    berechnet nach Read-/Hidden-Mutationen `feeds.unreadCount` direkt in SQLite
    neu und bump't `SQLiteDataInvalidation.statusVersionKey`, wodurch die
    Sidebar-Snapshots neu geladen werden.
  - SQLite-Migrationsabschluss 2026-07-03: Regel-Preview, Regel-Zählungen und
    rückwirkendes Anwenden bestehender Regeln laufen über
    `SQLiteRuleEvaluationStore` und leichte `RuleEngine.ArticleRuleSnapshot`s.
    Offline-Kopien liegen in `article_offline`; `SQLiteOfflineDownloadService`
    speichert Feed-Content oder geladene Originalseiten, Reader und Artikelliste
    lesen den Offline-Status aus SQLite. Die Artikel-Aufbewahrung löscht nun
    auch SQLite-Artikel samt Statuszeilen und korrigiert `feeds.unreadCount`.
  - Retention-Wiedererkennung 2026-07-03 ergänzt: Migration v9 legt
    `article_identity_history` an. `ArticleRetentionCleanupService` sichert vor
    dem Löschen alter SQLite-Artikel stabile Quellen-ID, Link, Titel-Hash,
    Seen-Zeitpunkte und letzten Status; `ArticleStore` stellt diesen Status
    beim späteren Wiederauftauchen eines Artikels wieder her.
  - NetNewsWire-artige Feed-Retention 2026-07-03 ergänzt: Migration v10 erweitert
    `feeds` um `articleRetentionMinimumArticles`. Globale Bereinigung und
    Feed-Overrides können nun eine Mindestanzahl neuester Artikel pro Feed
    behalten, damit selten aktualisierte Feeds nicht leergeräumt werden.
    OPML-Import spiegelt neu importierte Feeds nach SQLite; OPML-Export
    bevorzugt SQLite-Feed- und Feed-Tag-Snapshots und ergänzt nur Feed-
    Beschreibungen aus SwiftData. Einzelartikel-Export aus der SQLite-Liste
    nutzt `ArticleReaderSnapshot`, gespeicherten Offline-Volltext und Tag-Namen
    aus `article_tags`/`feed_tags`.
  - Sichtbarer Artikelfenster-/Command-Legacy-Pfad 2026-07-03 geschlossen:
    `SQLiteReaderView` meldet den geladenen `ArticleReaderSnapshot` nach oben,
    `ContentView` nutzt ihn für Artikel-Menüaktionen, Shortcuts, Link-/Share-
    Aktionen, Export und `In eigenem Fenster öffnen`. `ArticleWindowView` lädt
    separate Fenster über `SQLiteReaderView`, berechnet Vor-/Zurück-Navigation
    aus `TimelineStore(.all)` und hält keine SwiftData-`@Query<Article>` mehr.
  - UI-Parität zum main-Branch nachgezogen: `SQLiteFeedArticleListView` nutzt
    wieder die main-nahe `List(selection:)`-Darstellung mit Suchleisten-Chroming
    und Mark-read-/Filter-/Sortier-Toolbar; `SQLiteReaderView` nutzt Reader-
    Typografie, Anzeige-Picker, Textformat-Popover und die gewohnten Toolbar-
    Signale statt einer vereinfachten Ersatzoberfläche.
  - OPML-Import und `Alle Feeds aktualisieren` rufen Feeds nur noch begrenzt parallel ab
  - Sidebar nutzt keine globale Artikel-Query mehr für Badge-Signaturen; beim
    Lesen invalidieren `isRead`-Änderungen dadurch nicht mehr alle Sidebar-
    Badge-Daten
  - Der rechte Artikel-Inspector nutzt von `ReaderView` vorbereitete Snapshot-
    Werte für Feedname, Ordner, Lesezeit und Content-Verfügbarkeit; dadurch
    faultet der Inspector-Body keine Volltext-/Offline-Textfelder mehr.
  - Die Ordnerauswahl im rechten Artikel-Inspector liest Feed-Ordnernamen nur
    noch als leichten Snapshot und hält keine `@Query` auf alle Feeds mehr im
    SwiftUI-Body.
  - Die Artikelliste hält Feed-Titel für Zeilen-Metadaten als leichten
    `feedID -> title` Snapshot statt die Lookup-Map in jedem Body-Render aus
    einer `@Query(sort: \Feed.title)` neu zu bauen.
  - Artikelzeilen rendern sichtbare Werte über `ArticleListItemSnapshot` statt
    diese direkt aus der Row heraus aus dem SwiftData-`Article` zu lesen; die
    echte `Article`-Instanz bleibt in `ArticleListView` vorerst für Auswahl und
    Aktionen erhalten.
  - `Ungelesen`-Badge der intelligenten Ordner nutzt die gespeicherten `Feed.unreadCount` Werte
  - `Mit Stern`, `Ausgeblendet` und `Gespeichert` lesen ihre Sidebar-Badges aus
    gebündelten Status-Zählern
  - `Ungelesen` lädt für die Artikelliste bewusst alle Artikel und überlässt das Ausblenden gelesener Artikel der Anzeigeebene, damit gerade gelesene Artikel sichtbar bleiben können
  - Artikel-Listen berechnen sichtbare Artikel und die Anzahl ausgeblendeter gelesener Artikel in einem Durchlauf
  - Tag-Zuweisungsoptionen werden in Artikelzeilen nicht mehr beim Zeilen- oder Kontextmenü-Aufbau berechnet; `Tag zuweisen...` öffnet ein kleines Sheet, das verfügbare Tags erst bei Bedarf filtert und sortiert
  - Vordefinierte/einfache intelligente Ordner nutzen gezielte SwiftData-Queries statt alle Artikel im Speicher zu filtern
  - Reader-HTML-Parsing cached `NSRegularExpression` Instanzen und wandelt Textblöcke ohne `NSAttributedString`/WebKit in Plain Text um
  - Artikel-Listen bereiten Sortierung und Filterung gemeinsam vor, damit pro Render nicht doppelt sortiert wird
  - Artikelzeilen prüfen Original-Links über einen stateless Resolver statt pro Kontextmenü-Zugriff eine neue `ArticleViewModel`-Instanz zu erzeugen
  - Artikelzeilen und Artikel-Commands prüfen Link-Aktionsverfügbarkeit mit einem günstigen `http/https`-String-Check; echte `URL`-Objekte entstehen erst beim Ausführen der Link-Aktion
  - Artikelwechsel aktualisiert die Navigation aus der sichtbaren Liste, ohne Sortierung/Filterung erneut anzustoßen
  - Reader-Artikelwechsel faulten schwere Textfelder nicht mehr schon im SwiftUI-View-Aufbau; Feedname, Ordner und Tags starten als leichte Snapshot-Werte, damit die sichtbaren Metadaten nicht nachlaufen
  - Der Reader lädt den vollständigen Artikel-Snapshot über einen eigenen SwiftData-`ModelContext` im Hintergrund, statt `content`/`offlineContent` aus dem UI-`Article` zu faulten
  - Reader-Cache-Keys speichern nur kompakte Text-Fingerprints und keine zusätzlichen Volltext-Kopien
  - Reader-Detailbilder werden mit Ziel-Pixelgröße geladen, damit große Feedbilder nicht unnötig voll decodiert werden
  - Artikelzeilen lesen Feednamen über einen `feedID -> Feed.title` Lookup statt über `article.feed?.title`, damit `Alle Artikel` beim Lesen keine Feed-Relationship-Faults pro sichtbarer Zeile erzeugt
  - Beim automatischen Als-gelesen-markieren aktualisiert die Artikelliste `Feed.unreadCount` nicht mehr pro Artikelauswahl, sondern sammelt betroffene Feed-IDs und synchronisiert die Zähler beim debounced Persistenz-Flush per `fetchCount`
  - Die Artikelansicht bietet hinter den Ordner-/Tag-Chips ein Inline-Tag-Popover, das dieselbe Tag-Erstellungs- und Zuweisungslogik wie der rechte Inspector nutzt
  - Der Reader-Prefetch der Artikelliste bleibt leichtgewichtig und faultet keine `content`-/`offlineContent`-Volltexte, keine Feed-Relationships oder Nachbarartikel-Bilder mehr, damit sequentielles Lesen weniger CPU/I/O erzeugt
  - Native Reader- und Readability-Inhalte rendern per `LazyVStack`, damit lange Artikel beim Öffnen nicht vollständig als SwiftUI-View-Baum materialisiert werden
  - Der Reader zeigt beim Wechsel sofort eine leichte Summary-/Bild-Vorschau und vermeidet sichtbare Spinner für Reader-Bilder
  - Komplexe intelligente Ordner sortieren Bedingungen einmal vor dem Artikel-Loop und verwenden einen vorbereiteten Matcher
  - Reader-Bildblock-Erkennung nutzt eine einfache case-insensitive Suche statt einer Regex-Kompilierung im Loop
  - Tag-Badges in der Sidebar zählen per SwiftData-`fetchCount` über denselben Tag-Predicate wie die Artikelliste, statt Tag-/Feed-Artikel-Relationships zu traversieren
  - Lesestatus-Aktionen aktualisieren `Feed.unreadCount` auch dann über `Article.feedID`, wenn die `Article.feed`-Relationship im schnellen Query-Pfad nicht geladen ist
  - Bulk-Aktionen wie `Alle als gelesen markieren` synchronisieren betroffene Feed-Zähler per SwiftData-`fetchCount`, damit bereits falsch gespeicherte Badges wieder auf den echten ungelesenen Bestand fallen
  - Rückwirkend angewendete Hide-Regeln synchronisieren betroffene `Feed.unreadCount` Werte; der v3-Backfill korrigiert bestehende gespeicherte Sidebar-Zähler beim App-Start
  - Das Artikelansicht-Menü zeigt die Bulk-Option ausdrücklich als `Alle als gelesen markieren`
  - Feed-Refreshes laden bestehende Artikel per gezieltem `Article.feedID`-Fetch
    mit schlankem Property-Set statt über die komplette `feed.articles`-Relationship
  - Feed-Refreshes nutzen gespeicherte HTTP-Validatoren (`ETag`, `Last-Modified`
    und Body-Hash) für Conditional GET. Bei HTTP 304 oder identischem Body-Hash
    wird der Feed als unverändert behandelt und die teure Parse-/SwiftData-
    Verarbeitung übersprungen. Unveränderte Feeds schreiben außerdem keinen neuen
    Info-Logeintrag; bei identischen gespeicherten Validatoren wird auch das
    `Feed`-Objekt nicht neu gespeichert.
  - Der Refresh-Lookup lässt `Article.content`/`Article.offlineContent` weg und
    schreibt bestehende Artikelwerte nur bei echten Änderungen oder fehlenden
    Nachträgen
  - Die Refresh-Status-UI aktualisiert Batch-Startzustände gesammelt und animiert
    laufende Fortschrittsänderungen nicht mehr global
  - Sammel-Refreshes aus Hauptfenster, Start-Refresh und periodischem Background-
    Scheduler laufen über `FeedBackgroundRefreshService` mit eigenem SwiftData-
    Kontext pro Feed. Die UI übergibt nur Feed-Snapshots und erhält Status-Events
    sowie eine grobe Ergebnis-Summary zurück.
  - Feed-, Tag-, Smart-Filter- und einfache Smart-Folder-Artikellisten verwenden
    leichte `FetchDescriptor` mit `propertiesToFetch`; `Article.content` und
    `Article.offlineContent` bleiben aus dem Standard-Listenfetch heraus
  - Artikellisten laden initial 50 Artikel und erhöhen das SwiftData-`fetchLimit`
    beim Scrollen ans Listenende in 50er-Schritten
  - Die Nachlade-Zeile der Artikelliste ist an das aktuelle `fetchLimit`
    gebunden, damit `Ungelesen` bei sichtbarem Lade-Trigger mehrere Batches
    nacheinander laden kann, bis wieder ungelesene Artikel sichtbar werden
  - Die Pagination merkt sich den höchsten beobachteten Fetch-Count, damit
    Nachladen nicht stoppt, wenn gelesene Artikel aus einer `Ungelesen`-Query
    fallen und `articles.count` dadurch unter das aktuelle Limit sinkt
  - Sammel-Refreshes speichern Änderungen pro Batch statt pro Feed, um SwiftData-
    Query-Invalidierungen während laufender Aktualisierungen zu reduzieren
  - Start-Backfills und Orphan-Cleanup vermeiden vollständige
    `feed.articles`-Relationship-Faults; `Article.feed` wird dort nur noch als
    Fallback für alten Datenbestand ohne `feedID` berührt
  - Sidebar-Tag-Badges lesen Zähler aus `article_tags` und `feed_tags` über
    `TagStore.sidebarTags()` und `SQLiteSidebarState`
  - Sidebar-Tag-Zeilen lesen ihre Quelle ebenfalls aus `SQLiteSidebarState`
    statt aus einer SwiftData-`@Query<Tag>`
  - Sidebar-Smart-Folder-Badges lesen Status-Zähler aus SQLite über
    `ArticleStatusStore.sidebarSmartFolderBadgeSnapshot()` und
    `SQLiteSidebarState`
  - Direkte Tag-Filter verwenden `TimelineScope.tag` und die SQLite-
    Artikelliste/Reader-Kette; Feed-Tags werden dabei über `feed_tags`
    berücksichtigt
  - Bestehende SwiftData-Feed-Tags werden beim App-Start nach SQLite gespiegelt,
    damit Altbestand ohne erneutes Öffnen der Feed-Eigenschaften in Tag-Filtern
    und Sidebar-Badges auftaucht
  - Feed-Eigenschaften zeigen die letzten 20 Feed-Logs aus SQLite-`feed_logs`,
    statt `FeedLogEntry`-Objekte über SwiftData zu laden
  - Feed-Eigenschaften und Feed-Verwaltungszeilen laden neuesten Artikel und
    Artikel der letzten 7 Tage über `ArticleStore.feedPropertiesMetrics` aus
    SQLite, statt `FeedPropertiesQuery` auf SwiftData-Artikeln zu verwenden.
    Bearbeitbare Feed-Eigenschaften wie Name, Ordner, Intervall,
    Benachrichtigungen, Feed-Tags und Retention werden dort ebenfalls über
    SQLite-Stores geschrieben.
  - Vordefinierte SmartFilter verwenden `TimelineScope.smartFilter` und die
    SQLite-Artikelliste/Reader-Kette, statt globale SwiftData-Artikelqueries zu
    materialisieren
  - Smart-Folder-Settings und Smart-Folder-Editor laufen SQLite-first über
    `SQLiteSmartFolderStore`; Trefferzahlen/Preview nutzen
    `TimelineStore.count(scope: .smartFolder(...))`, statt Artikel per
    SwiftData zu materialisieren
  - Feed-Ordner, Regel- und Smart-Folder-Definitionen haben eigene SQLite-
    Tabellen und Stores; bestehende SwiftData-Verwaltungsdaten werden beim
    App-Start nach SQLite gespiegelt
  - SQLite-FTS-Fundament ergänzt: Migration v4 legt `article_search` mit FTS5
    und Triggern für Insert/Update/Delete auf `articles` an;
    `ArticleStore.searchArticles` liefert Treffer als `ArticleListSnapshot`s
  - Die sichtbare Artikellisten-Suche im SQLite-Hauptpfad nutzt FTS5 über
    `TimelineStore.articles(... searchText:)`, normalisiert Suchtext vor
    `MATCH` und filtert direkt in SQLite innerhalb des aktuellen Feed-, Tag-
    oder SmartFilter-Scopes
  - Das separate Suchfenster (`Cmd+F`) lädt seine Ergebnisliste im SQLite-
    Hauptpfad über `ArticleStore.searchArticles(state:)`; Feed-, Tag-, Datums-
    und Statusfilter werden SQL-seitig kombiniert und funktionieren auch ohne
    Suchtext
  - Status-Badges beobachten nur eine kleine Query auf Stern-/Archiv-/
    Hidden-Artikel
  - Artikelzeilen laden Vorschaubilder über größenbegrenzte Thumbnails aus dem
    gemeinsamen Bildcache; der Disk-Cache speichert weiter das Original, aber die
    Liste hält nur kleine `NSImage`-Instanzen im Memory-Cache
  - Die sichtbare Artikellisten-Suche durchsucht nur noch Titel und
    Zusammenfassung, damit `Article.content` und `Article.offlineContent` beim
    Tippen nicht aus dem leichten Listenfetch nachgeladen werden
- **Zu beachten:**
  - SwiftData-Queries immer mit gezielten Predicates; bewusste Ausnahme ist der Default-Ordner `Ungelesen`, weil dort die Anzeigeebene gelesene Artikel für Feed-ähnliches Verhalten temporär sichtbar halten muss
  - Weiteres Lazy Loading für schwere Inhalte außerhalb der sichtbaren Listenzeilen
  - Spotlight-Index im Hintergrund aufbauen (nicht im Main Thread)
  - Automatisches Datenbank-Cleanup via Feature 17.3

### 26.3 Shortcuts / Automator-Integration
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren via `AppIntents` Framework (macOS 13+):**
  - Feed aktualisieren
  - Feed hinzufügen
  - Artikel als gelesen markieren
  - Artikel exportieren

---

## Implementierungs-Reihenfolge (Empfehlung für Codex)

Folgende Reihenfolge berücksichtigt Abhängigkeiten. Features mit (*) sind Voraussetzung für nachfolgende.

### Phase 1 — Fundament & Artikel-Modell
1. **Feature 22.1** * — Artikel-Modell erweitern (`isArchived`, `isHidden`) — erledigt
2. **Feature 2.5** — Artikel-Liste Anzeige-Logik (gelesene ausblenden, Button am Ende) — erledigt
3. **Feature 2.4** — Kontextmenü vollständig ausbauen (inkl. Archivieren, Exportieren, Teilen) — erledigt
4. **Feature 2.2** — Sortierung GUI (Toolbar-Dropdown + Menüleiste) — erledigt
5. **Feature 2.3** — Filterung GUI (Toolbar-Dropdown) — erledigt

### Phase 2 — Regeln & Intelligente Ordner
6. **Feature 16.3** * — Artikel ausblenden via Regel + Smart Filter "Ausgeblendet" — erledigt
7. **Feature 5.2** — Regeln Settings-Design (Drag & Drop Liste, alle 3 Aktionen) — erledigt
8. **Feature 16.1/16.2** — Intelligente Ordner (eigener Sidebar-Abschnitt, Sheet, Live-Vorschau, 3 vordefinierte) — erledigt
9. **Feature 3.2** — Smart Filter erweitern — entfällt, durch Intelligente Ordner ersetzt

### Phase 3 — Benachrichtigungen
10. **Feature 10.3** * — Badge-Zähler App-Icon + Einstellungs-Kategorie Benachrichtigungen — erledigt
11. **Feature 10.1** — Feed-Benachrichtigungen pro Feed (Toggle in Feed-Eigenschaften, Zusammenfassung) — erledigt
12. **Feature 10.2** — Regelbasierte Benachrichtigungen (Aktion im RuleWizard, anpassbarer Text, Priorität Normal/Kritisch) — erledigt

### Phase 4 — Feed hinzufügen & Verwaltung
13. **Feature 4.1** — Website Feed-Suche (Auto-Erkennung, Liste gefundener Feeds) — erledigt
14. **Feature 12.4** — Feed-Vorschau vor dem Abonnieren (5 Artikel im Sheet) — erledigt
15. **Feature 17.3** — Automatisches Löschen (90 Tage Standard, pro Feed, Ausnahmen Stern + Archiv)
16. **Feature 17.1** — Automatisches Offline-Speichern bei Stern (Toggle in Einstellungen) — erledigt

### Phase 5 — Export & Teilen
17. **Feature 18.1** — Artikel exportieren (Markdown/Text/HTML mit Vorschau erledigt; Offline-Bilder für Markdown/HTML als ZIP-Paket erledigt; Datei-Teilen erledigt; PDF/DOCX zurückgestellt)
18. **Feature 18.2** — Batch-Export (Cmd+Klick Mehrfachauswahl, ZIP oder eine Datei)
19. **Feature 7.2** — OPML Export-Dialog (Checkboxen, Menüleiste + Einstellungen) — erledigt

### Phase 6 — Suche
20. **Feature 9.1** — Volltext-Suche Core-Slice (Cmd+F, Suchleiste, Bereich und Umfang) — erledigt
20a. **Feature 9.2** — Erweiterte Suchfilter (Feed, Tag, Zeitraum, Status) — erledigt
21. **Feature 9.3** — Spotlight-Integration (CSSearchableItem, Toggle in Einstellungen)

### Phase 7 — Customization & Einstellungen
22. **Feature 8.2** — Neue Einstellungs-Kategorien (Benachrichtigungen, Artikel, Menubar, Darstellung erweitern)
23. **Feature 19.1** — Artikel-Liste anpassen (Vorschautext-Zeilen, Bildposition, Datum-Format, Feed-Name, Ungelesen-Markierung)
24. **Feature 19.2** — Sidebar anpassen (Zähler, Favicons, Smart Filter ein/ausblenden)
25. **Feature 19.3** — Reader anpassen (Textbreite, Artikelbild)
26. **Feature 19.4** — Toolbar anpassen (macOS Standard `Symbolleiste anpassen...`)
27. **Feature 19.5** — Verhalten (Gelesen beim Öffnen, externe Links, Bilder laden, App-Start)

### Phase 8 — Menubar & Fenster
28. **Feature 21.1** — Menubar-App (Dropdown, Badge, ohne Dock, konfigurierbar)
29. **Feature 24.1** — Mehrfenster (Cmd+Return + Kontextmenü, Fenster-Zustand speichern)

### Phase 9 — Reader Features
30. **Feature 11.1** — Lesedauer im Reader anzeigen — erledigt; keine Anzeige in der Artikel-Liste
31. **Feature 11.2** — Lesefortschritt (Fortschrittsbalken, Scroll-Position speichern) — zurückgestellt
32. **Feature 1.8** — Vollartikel-Extraktion (Readability.js, dritter Reader-Modus)

### Phase 10 — Statistiken
32. **Feature 14.1** — Lese-Statistiken (separates Fenster, Heatmap, Top Feeds, Cmd+Shift+S)
33. **Feature 14.2** — Feed-Statistiken in Feed-Info-Ansicht integrieren

### Phase 11 — Deep Links & Shortcuts
34. **Feature 23.1** — Share Extension (In Feedivo öffnen aus anderen Apps)
35. **Feature 23.2** — URL-Schema `feedivo://` (add, article)
36. **Feature 26.3** — AppIntents / Shortcuts Integration (Feed aktualisieren, hinzufügen, gelesen, exportieren)

### Phase 12 — Drucken & Qualität
37. **Feature 25.1** — Drucken via Cmd+P (Reader oder Original, User wählt im Druckdialog)
38. **Feature 26.2** — Performance-Optimierung (Paginierung, Lazy Loading, Query-Optimierung für 500 Feeds / 100'000 Artikel)

---

## Zurückgestellt (nach v1)

- **Feature 12.2** — Feed-Suche via Discover (Feedly API kostenpflichtig)
- **Feature 14.3** — Statistik-Daten exportieren
- **Feature 15.2** — Feeds per Drag & Drop umsortieren
- **Feature 18.1c** — PDF- und DOCX-Export für einzelne Artikel
- **Feature 18.3** — Drittanbieter-Integration (Readwise, Obsidian, Pocket)
- **Feature 26.1** — Barrierefreiheit / VoiceOver
