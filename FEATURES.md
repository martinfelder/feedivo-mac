# Feedivo macOS — Feature Liste
> **Für Codex:** Diese Datei ist die massgebliche Quelle für alle Features.
> Implementiere nur Features mit Status ✅ Entschieden oder 🔨 In Arbeit.
> Features mit 💬 In Diskussion noch NICHT implementieren — warten auf Entscheid.
> Features mit ⏸️ Zurückgestellt kommen nach v1.
>
> Status-Legende:
> ✔️ Fertig | 🔨 In Arbeit (teilweise umgesetzt) | ✅ Entschieden (bereit zur Implementierung) | 💬 In Diskussion | ⏸️ Zurückgestellt
>
> Zuletzt aktualisiert: 2026-06-25

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
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Teilen via macOS Share Sheet — ausgelöst aus Kontextmenü (Feature 2.4)
  - Kein separater Teilen-Button im Reader
  - Geteilt wird: Titel + URL des Artikels

### 1.7 Im Browser öffnen
- **Status:** ✔️ Fertig
- **Umgesetzt:** `Original öffnen` im Inspector, nutzt Standard-Browser

### 1.8 Reader-Ansicht (Vollartikel-Extraktion)
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Dritter Modus im Reader (neben nativem SwiftUI Text und WKWebView)
  - Toggle in der Reader-Toolbar zum Wechseln zwischen den 3 Modi
  - Technisch: Readability.js via WKWebView (Option A — Mozilla Standard)
  - Extraktion startet erst wenn User explizit auf "Artikel laden" Button klickt
  - Braucht Internet-Verbindung — lädt Originalseite und extrahiert Hauptinhalt
  - Keine automatische Extraktion beim Moduswechsel

### 1.9 Schriftgrösse / Font anpassen
- **Status:** ✔️ Fertig
- **Umgesetzt:** `ReaderFontPreset` (18 Presets), `ReaderTypography`

### 1.10 Link in Zwischenablage kopieren
- **Status:** ✔️ Fertig
- **Umgesetzt:** Inspector + `Cmd+L`

### 1.11 Regel erstellen aus Artikel
- **Status:** ✔️ Fertig
- **Umgesetzt:** `RuleWizardView` vorausgefüllt aus Artikel-Kontext

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
  11. Exportieren... als Markdown-Datei (`.md`) mit Metadaten und lesbarem Artikeltext
  12. ─────────────────
  13. Alle als gelesen markieren (gilt für aktuell sichtbare Liste)
- **Bewusst später / optional:** PDF- und DOCX-Export als eigene Formate, falls nach dem Markdown-Slice noch gewünscht.

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
- **Entscheidung:** Die Suche startet per Button `Suchen`, nicht automatisch beim Tippen, damit keine unnötigen Netzwerkabrufe pro Tastendruck entstehen.

### 4.2 Feed bearbeiten
- **Status:** ✔️ Fertig
- **Umgesetzt:** `FeedPropertiesView`, `FeedRenameView`

### 4.3 Feed löschen
- **Status:** ✔️ Fertig
- **Umgesetzt:** `FeedViewModel.deleteFeed`, Bestätigungsdialog

### 4.4 Manueller Refresh
- **Status:** ✔️ Fertig
- **Umgesetzt:** `refreshFeed` / `refreshAllFeeds`, `operationProgress` Overlay

### 4.5 Automatischer Refresh
- **Status:** ✔️ Fertig
- **Umgesetzt:** `NSBackgroundActivityScheduler`, 15/30/60/120 Min.

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
  - Doppelklick öffnet RuleWizard zum Bearbeiten
  - Rechtsklick: Bearbeiten / Duplizieren / Löschen
  - `+` Button für neue Regel
  - "Alle Regeln jetzt anwenden" Button (rückwirkend auf bestehende Artikel)
  - Anzahl betroffener Artikel pro Regel anzeigen
- **Regel-Aktionen:**
  - Tag zuweisen (bereits vorhanden)
  - Benachrichtigung auslösen (neu — siehe Feature 10.2)
  - Artikel ausblenden (umgesetzt — siehe Feature 16.3)
- **Noch offen (nicht jetzt implementieren):**
  - Echtes Drag & Drop für die Reihenfolge; für v1 bewusst stabile Reihenfolge-Buttons
  - Regex als Operator

---

## 6. iCloud Sync

### 6.1 Sync via CloudKit
- **Status:** ⏸️ Zurückgestellt (M4)
- **Grund:** Core-Features haben Vorrang — nach v1

---

## 7. OPML

### 7.1 OPML Import
- **Status:** ✔️ Fertig
- **Umgesetzt:** `OPMLImportReviewView`, zweiphasiger Import, Drag & Drop,
  Übernahme des gewählten bzw. gespeicherten Aktualisierungsintervalls für neu
  importierte Feeds

### 7.2 OPML Export
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Umgesetzt:** `OPMLService`, `OPMLDocument` technisch vorhanden
- **Zu implementieren:**
  - Auslösen via Menüleiste `Datei → Exportieren → OPML...` UND Einstellungen-Button
  - Export-Dialog öffnet sich mit folgenden Optionen (Checkboxen):
    - Feed-URLs + Titel (immer aktiviert, nicht deaktivierbar)
    - Ordner-Struktur als OPML-Gruppen
    - Tags (als Kategorie-Attribut)
    - Feed-Beschreibung (Metadaten)
  - Standard-Dateiname: `Feedivo-Export-YYYY-MM-DD.opml`
  - Favorisierte Artikel werden NICHT im OPML exportiert — das ist Sache von Feature 18

---

## 8. Einstellungen

### 8.1 Bestehendes Settings-Fenster
- **Status:** ✔️ Fertig
- **Umgesetzt:** Kategoriennavigation (Allgemein, Darstellung, Feeds, Aktualisierung, Tags & Regeln, Sync, Offline-Lesen)

### 8.2 Neue Einstellungs-Kategorien (zu implementieren)
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren — neue oder erweiterte Kategorien:**
  - **Benachrichtigungen:** Globale Einstellungen (Badge-Zähler, Stille Stunden)
  - **Artikel:** Auto-Löschen (Standard 90 Tage), Anzeige-Logik, Vorschautext-Zeilen
  - **Menubar:** Anzahl Artikel im Dropdown, Klick-Verhalten (Feedivo / Browser), Dock-Icon ausblenden
  - **Darstellung (erweitern):** Vorschaubild an/aus, Bildposition (links/rechts), Reader-Textbreite, Favicons, Ungelesen-Zähler
  - **Umgesetzt:** Option `Gelesene Feeds in der Seitenleiste anzeigen`

---

## 9. Suche

### 9.1 Volltext-Suche
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Globale Suche via `Cmd+F` in der Toolbar (immer sichtbar)
  - Schnellfilter oben in der Artikel-Liste (kontextuell)
  - User kann Suchbereich einschränken: Titel / Zusammenfassung / Volltext / Alles
  - User kann Umfang wählen: nur aktueller Feed oder feedübergreifend
  - Suchresultate in der Artikel-Liste anzeigen

### 9.2 Suchfilter
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Filteroptionen in der Suche: Feed / Tag / Zeitraum / Status (gelesen/ungelesen)
  - Suchbereich-Auswahl: Titel / Zusammenfassung / Volltext
  - Umfang: aktueller Feed oder alle Feeds

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
- **Status:** 🔨 In Arbeit
- **Umgesetzt:** Lesezeit-Berechnung in `ReaderMetadataFormatter` vorhanden
- **Zu implementieren:**
  - Lesedauer auch in der Artikel-Liste anzeigen (nicht nur im Reader)

### 11.2 Lesefortschritt
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Fortschrittsbalken oben im Reader (dünne Linie die sich beim Scrollen füllt)
  - Lesefortschritt wird gespeichert — beim erneuten Öffnen startet der Artikel an der gleichen Stelle
  - Technisch: Scroll-Position in `Article` speichern (SwiftData)

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
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Umgesetzt:** `OfflineDownloadService`, `Article.offlineContent`, manuell via Kontextmenü
- **Zu implementieren:**
  - Einstellungen → Offline-Lesen: Toggle "Artikel mit Stern automatisch offline speichern"

### 17.2 Artikel-Zustände
- **Status:** ✅ Entschieden — siehe Feature 22.1

### 17.3 Automatisches Löschen
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Globale Einstellung: Artikel nach X Tagen löschen (Standard: 90 Tage)
  - Pro Feed überschreibbar in Feed-Eigenschaften
  - Alle Artikel werden gelöscht — unabhängig ob gelesen oder ungelesen
  - Ausnahmen (niemals auto-gelöscht): Archivierte Artikel, Artikel mit Stern
  - Einstellungs-Kategorie "Artikel" im Settings-Fenster

### 17.4 Artikel-Liste Anzeige-Logik
- **Status:** ✅ Entschieden — siehe Feature 2.5

---

## 18. Artikel exportieren

### 18.1 Einzelnen Artikel exportieren
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Auslösen: via Kontextmenü (Feature 2.4) und Reader-Toolbar
  - Export-Dialog mit Format-Auswahl:
    - PDF — 1:1 Reader-Darstellung (so wie Artikel im Reader erscheint)
    - DOCX — mit Checkbox "Bilder einbetten" (User entscheidet)
    - Markdown, Plain Text, HTML (in v1 wenn machbar, sonst nach v1)
  - Metadaten mitexportieren: optionale Checkbox im Export-Dialog (Titel, Autor, Datum, Feed-Name, URL, Tags)
  - Export via eigenem Dialog (PDF/DOCX mit Optionen) UND macOS Share Sheet (Schnellzugriff)

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
  - Maximale Textbreite: schmal / mittel / breit
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
  - Keine Feeds: First-Run-Wizard auslösen (bereits vorhanden)
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
- **Status:** ✅ Entschieden — bereit zur Implementierung
- **Zu implementieren:**
  - Artikel in separatem Fenster öffnen via `Cmd+Return` und Kontextmenü
  - Fenster-Zustand beim Beenden speichern und beim Start wiederherstellen
  - `WindowGroup` in SwiftUI aktivieren für Mehrfenster-Unterstützung

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
- **Umgesetzt:**
  - OPML-Import und `Alle Feeds aktualisieren` rufen Feeds nur noch begrenzt parallel ab
  - Sidebar lädt keine globale Artikelliste mehr nur für Smart-Folder-Badges
  - `Ungelesen`-Badge der intelligenten Ordner nutzt die gespeicherten `Feed.unreadCount` Werte
  - Artikel-Listen berechnen sichtbare Artikel und die Anzahl ausgeblendeter gelesener Artikel in einem Durchlauf
  - Tag-Zuweisungsoptionen werden in Artikelzeilen erst im Kontextmenü berechnet, nicht mehr bei jedem Zeilen-Render
  - Vordefinierte/einfache intelligente Ordner nutzen gezielte SwiftData-Queries statt alle Artikel im Speicher zu filtern
  - Reader-HTML-Parsing cached `NSRegularExpression` Instanzen und wandelt Textblöcke ohne `NSAttributedString`/WebKit in Plain Text um
  - Artikel-Listen bereiten Sortierung und Filterung gemeinsam vor, damit pro Render nicht doppelt sortiert wird
  - Artikelzeilen prüfen Original-Links über einen stateless Resolver statt pro Kontextmenü-Zugriff eine neue `ArticleViewModel`-Instanz zu erzeugen
  - Artikelwechsel aktualisiert die Navigation aus der sichtbaren Liste, ohne Sortierung/Filterung erneut anzustoßen
  - Komplexe intelligente Ordner sortieren Bedingungen einmal vor dem Artikel-Loop und verwenden einen vorbereiteten Matcher
  - Reader-Bildblock-Erkennung nutzt eine einfache case-insensitive Suche statt einer Regex-Kompilierung im Loop
  - Tag-Badges in der Sidebar zählen per SwiftData-`fetchCount` über denselben Tag-Predicate wie die Artikelliste, statt Tag-/Feed-Artikel-Relationships zu traversieren
  - Lesestatus-Aktionen aktualisieren `Feed.unreadCount` auch dann über `Article.feedID`, wenn die `Article.feed`-Relationship im schnellen Query-Pfad nicht geladen ist
  - Bulk-Aktionen wie `Alle als gelesen markieren` synchronisieren betroffene Feed-Zähler per SwiftData-`fetchCount`, damit bereits falsch gespeicherte Badges wieder auf den echten ungelesenen Bestand fallen
  - Das Artikelansicht-Menü zeigt die Bulk-Option ausdrücklich als `Alle als gelesen markieren`
- **Zu beachten:**
  - SwiftData-Queries immer mit gezielten Predicates — nie alle Artikel auf einmal laden
  - Artikel-Liste mit Paginierung (50 Artikel pro Batch, mehr beim Scrollen)
  - Lazy Loading für Bilder und Inhalte
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
16. **Feature 17.1** — Automatisches Offline-Speichern bei Stern (Toggle in Einstellungen)

### Phase 5 — Export & Teilen
17. **Feature 18.1** — Artikel exportieren (Export-Dialog: PDF, DOCX mit Bilder-Checkbox, Metadaten-Checkbox, Share Sheet)
18. **Feature 18.2** — Batch-Export (Cmd+Klick Mehrfachauswahl, ZIP oder eine Datei)
19. **Feature 7.2** — OPML Export-Dialog (Checkboxen, Menüleiste + Einstellungen)

### Phase 6 — Suche
20. **Feature 9.1/9.2** — Volltext-Suche (Cmd+F global + Schnellfilter in Liste, Bereich wählbar)
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
30. **Feature 11.1** — Lesedauer in Artikel-Liste anzeigen
31. **Feature 11.2** — Lesefortschritt (Fortschrittsbalken, Scroll-Position speichern)
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

- **Feature 6.1** — iCloud Sync via CloudKit
- **Feature 12.2** — Feed-Suche via Discover (Feedly API kostenpflichtig)
- **Feature 14.3** — Statistik-Daten exportieren
- **Feature 15.2** — Feeds per Drag & Drop umsortieren
- **Feature 18.3** — Drittanbieter-Integration (Readwise, Obsidian, Pocket)
- **Feature 26.1** — Barrierefreiheit / VoiceOver
