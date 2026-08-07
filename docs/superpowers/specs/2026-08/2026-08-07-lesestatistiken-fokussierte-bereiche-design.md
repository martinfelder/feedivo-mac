# Design: Lesestatistiken neu gegliedert in fokussierte Bereiche

**Datum:** 2026-08-07
**Status:** Zur Review

## Kontext

Das bestehende Statistik-Fenster (`StatisticsWindowView.swift`, Feature 14, seit 2026-07-10)
zeigt ein flaches Raster aus 6 gleichförmigen Kennzahlen-Kacheln, eine kleine GitHub-Style-
Heatmap und zwei Top-5-Listen (Feeds/Tags nach Artikelanzahl). Der Nutzer ist mit der
Umsetzung aus drei Gründen unzufrieden:

1. **Die Lesezeit-Zahlen sind schlicht falsch.** `articles.estimatedReadingMinutes` wird beim
   Anlegen eines Artikels nie befüllt (`ArticleUpsertInput` übergibt den Parameter an keiner
   der beiden Aufrufstellen — `SQLiteFeedRefreshService.swift:136`,
   `SQLiteFeedSubscriptionService.swift:171` — Default bleibt `nil`) und auch später nie per
   `UPDATE` nachgetragen. Die Lesezeit-Schätzung existiert zwar bereits
   (`ReaderMetadataFormatter`, 200 Wörter/Minute), aber ausschließlich für die Anzeige im
   Reader — nie geschrieben in die DB-Spalte, aus der `StatisticsStore` "Ø Lesezeit/Tag",
   "Gesamt-Lesezeit" und die Pro-Feed-Lesezeit liest. Diese Werte sind dadurch **strukturell
   immer 0**, unabhängig vom tatsächlichen Leseverhalten — kein Geschmacksproblem, ein echter
   Bug.
2. **Die Kacheln wirken uniform, ohne Fokuspunkt.** Sechs optisch gleichwertige Kacheln lassen
   auf den ersten Blick nicht erkennen, was eigentlich interessant ist.
3. **Die Heatmap wirkt nicht wertig** — klein, in eine Karte gequetscht, wie ein Nebenprodukt
   statt ein eigenständiges, aussagekräftiges Element.

Zusätzlich zeigen die aktuellen Top-Feeds/Top-Tags-Listen reine **Artikelanzahl**, nicht
**Lesezeit** — für die Frage "wo geht meine Zeit wirklich hin" ist Anzahl irreführend (ein
Feed mit vielen kurzen Artikeln wirkt wichtiger als einer mit wenigen langen).

Drei Stoßrichtungen wurden besprochen (siehe „Betrachtete Ansätze"), der Nutzer hat sich für
eine Neugliederung in fokussierte Bereiche entschieden, ergänzt um einen leichten narrativen
Akzent (ein kurzer Erkenntnis-Satz). Ein HTML-Mockup im exakten App-Designsystem
(`RuleDialogTheme.swift`-Tokens) wurde iterativ abgestimmt — insbesondere die Heatmap-
Zellgröße (91 Tage × 7 Zeilen), die von zu groß (auf volle Breite gestreckt) über zu klein
(9px fix) auf **18px Zellgröße, 4px Abstand** landete. Diese Maße sind Teil der Freigabe.

## Ziel

Das Statistik-Fenster so umbauen, dass (a) die Lesezeit-Werte tatsächlich stimmen, (b) ein
klarer visueller Fokuspunkt existiert statt sechs gleicher Kacheln, und (c) die App
Erkenntnisse zeigt, die der Nutzer explizit wollte: Lesegewohnheiten über Zeit, wo die
Lesezeit wirklich hingeht, und welche Feeds er abonniert, aber kaum liest.

## Betrachtete Ansätze

1. **Minimal-invasiv** (verworfen): Bug fixen, bestehende Kachel-Struktur behalten, 2–3
   Kacheln ergänzen. Löst das "kein Fokuspunkt"-Problem nicht — macht das Raster eher voller.
2. **Fokussierte Bereiche** (gewählt): Klar getrennte Abschnitte statt einem flachen Raster —
   jeder Abschnitt beantwortet eine Frage. Ein Hero-Bereich (Serie + große Heatmap) statt
   sechs gleicher Kacheln, ergänzt um einen kurzen Erkenntnis-Satz (leichter Akzent aus
   Ansatz 3, siehe unten).
3. **Narrativ/„Wrapped"-Stil** (verworfen als Hauptform, ein Element übernommen): Eine große
   Hero-Grafik plus Erkenntnis-Sätze in Prosa als Hauptform. Zu unvorhersehbar/spielerisch als
   alleiniges Organisationsprinzip für ein Werkzeug, das man wiederholt aufruft — aber der
   Erkenntnis-Satz-Gedanke ist als einzelnes Element im Hero-Bereich übernommen worden.

## Layout

Kopfzeile (Titel, Untertitel, Zeitraum-Segmented-Control 7 Tage/30 Tage/Gesamt) und Fußzeile
(CSV-Export-Button) bleiben strukturell unverändert. Dazwischen, von oben nach unten:

### 1. Hero: Serie + Aktivität

Eine Karte, zweigeteilt (linke Spalte fix 200pt, rechte Spalte flexibel, Trennlinie
dazwischen — wie im abgestimmten Mockup):

- **Links** (`hero-streak`): großer Serien-Wert (56pt, fett, `tabular-nums`,
  Tracking −1.5pt — bewusst deutlich größer als die bisherige 22pt-Kachelzahl, das ist der
  eine visuelle Risiko-Moment dieser Neugestaltung), Label "in Folge gelesen", darunter
  "Längste Serie: N Tage", darunter ein kurzer, durch eine Trennlinie abgesetzter
  Erkenntnis-Satz (siehe „Erkenntnis-Satz" unten).
- **Rechts** (`hero-heatmap`): die vergrößerte 91-Tage-Heatmap. Zellgröße **18×18pt**, Radius
  4pt, Abstand 4pt zwischen Zellen (fest, nicht mehr proportional zur verfügbaren Breite
  gestreckt — das war der ursprüngliche "zu groß"-Fehler). Wochentag-Label-Spalte links
  (Mo/Mi/Fr, wie bisher), Monats-Kürzel-Zeile oben, Legende ("Weniger" … "Mehr") unten
  rechtsbündig. Inhaltlich unverändert zur bestehenden `StatisticsHeatmapView`-Logik
  (Quartils-Buckets 0–4 relativ zum Tagesmaximum im Fenster) — nur Zellgröße und
  Einbettungskontext ändern sich.

Beide Spalten sind vertikal zentriert, damit unterschiedliche Inhaltshöhen (z. B. kein
Erkenntnis-Satz bei zu wenig Daten) nicht zu einem schiefen Hero führen.

### 2. Überblick-Leiste (bewusst zweitrangig)

Eine schmale, einzeilige Karte mit genau 3 Werten (statt bisher 6 Kacheln), durch dünne
Trennlinien getrennt: "N gelesen (Zeitraum)" + Trend-Prozent, "Ø Artikel/Tag",
"Lesezeit gesamt". Deutlich kompakter als der bisherige Kachel-Block — dient als knappe
Kennzahlen-Referenz, nicht als visueller Schwerpunkt.

### 3. Abschnitt „Gewohnheiten"

Untertitel: "Wann du typischerweise liest". Zwei Karten nebeneinander:

- **Wochentag**: 7 vertikale Balken (Mo…So), Höhe proportional zur gelesenen Artikelanzahl
  an diesem Wochentag. Der höchste Balken ist hervorgehoben (volle Akzentfarbe statt
  40 %-Mischung), sein Label fett.
- **Tageszeit**: 5 horizontale Balken für feste Tagesabschnitte — Morgens (6–11 Uhr),
  Mittags (11–14 Uhr), Nachmittags (14–18 Uhr), Abends (18–23 Uhr), Nachts (23–6 Uhr) — mit
  Prozentanteil an der gelesenen Gesamtmenge. Der höchste Balken ist analog hervorgehoben.

Beide Verteilungen laufen über ein **festes 91-Tage-Fenster** (dasselbe wie die Heatmap),
unabhängig vom Zeitraum-Picker — bei 7 Tagen wäre die Stichprobe für ein Muster wie
"Wochentag" zu klein, um aussagekräftig zu sein.

### 4. Abschnitt „Aufmerksamkeit"

Untertitel: "Wo deine Lesezeit wirklich hingeht — nicht nur die Artikelanzahl". Zwei Karten
nebeneinander, je eine Rangliste mit bis zu 5 Einträgen:

- **Top-Feeds nach Lesezeit**: Favicon (echtes Bild über die bestehende
  `CachedRemoteImageView`/Fallback-Icon-Logik aus der heutigen `feedFaviconView` — **keine**
  Monogramm-Kreise; die Buchstaben-Icons im Mockup waren nur Platzhalter für die
  Design-Abstimmung), Feed-Titel, sekundär die Artikelanzahl, ein proportionaler Balken,
  rechtsbündig die Lesezeit ("2 Std 10"/"41 Min" — bestehendes `DateComponentsFormatter`-
  Muster aus `formattedTotalReadingTime`).
- **Top-Tags nach Lesezeit**: analog, aber mit einem Farbpunkt statt Favicon — echte
  `TagColorPalette.color(for: tag.colorHex)`-Farbe des jeweiligen Tags (bestehendes Muster
  aus der heutigen `topTagRow`), keine beliebige Mockup-Farbe.

Beide Ranglisten respektieren den Zeitraum-Picker (7/30 Tage/Gesamt) — wie die bisherigen
Top-Feeds/Top-Tags-Listen, nur jetzt nach `SUM(estimatedReadingMinutes)` statt `COUNT(*)`
sortiert.

### 5. Abschnitt „Feed-Gesundheit"

Untertitel: "Diese Feeds sammelst du, liest sie aber kaum — Kandidaten zum Abbestellen". Eine
Karte mit bis zu 5 Zeilen: Feed-Name, "N ungelesen · M insgesamt", eine dünne Lesequote-Leiste
in Warnfarbe (`#FF9F0A`, bereits Teil der App-Palette — z. B. `RuleDialogTagSwatches`) mit
Prozentwert, und ein **funktionierender** "Abbestellen"-Button.

**Auswahlkriterium** (all-time, unabhängig vom Zeitraum-Picker — "kaum gelesen" ist ein
Langzeit-Signal, kein 7-Tage-Ausschnitt): Feeds mit **mindestens 20 Artikeln insgesamt**,
sortiert nach Lesequote (gelesen/gesamt) aufsteigend, die 5 niedrigsten. Die
Mindest-Artikelzahl verhindert, dass ein frisch abonnierter Feed mit einem einzigen
ungelesenen Artikel fälschlich als "ignoriert" auftaucht. Sind keine Feeds mit ≥20 Artikeln
und niedriger Quote vorhanden, bleibt der Abschnitt leer (kein "0 Feeds gefunden"-Rauschen —
analog zum bestehenden Leer-Zustand-Muster bei Top-Feeds/Top-Tags).

**Abbestellen-Klick**: löst denselben bestehenden Lösch-Flow wie im Feed-Organizer aus
(`FeedManagementOrganizerView.swift`s `@State private var feedPendingDeletion`-Muster +
`.confirmationDialog(presenting:)` — derselbe Bestätigungsdialog-Wortlaut, kein neuer). Nach
erfolgreicher Löschung lädt das Statistik-Fenster seine Daten neu (bestehendes
`loadStatistics()`), die Zeile verschwindet dadurch aus der Liste.

### Erkenntnis-Satz

Ein einzelner, deterministisch aus den Gewohnheiten-Daten abgeleiteter Satz, kein Freitext/
keine KI-Generierung — reine Formatierungslogik, analog zum bestehenden
`L10n.statisticsStreakText(current:longest:)`-Muster:

- Basis: "Du liest am meisten **{Wochentag}{Tageszeit-Adverb}**." — {Wochentag} = Name des
  Wochentags mit den meisten gelesenen Artikeln im 91-Tage-Fenster, {Tageszeit-Adverb} = der
  Tagesabschnitt mit dem höchsten Anteil ("morgens"/"mittags"/"nachmittags"/"abends"/
  "nachts"), z. B. "Du liest am meisten dienstagabends."
- Optionaler Zusatz, wenn Samstag+Sonntag zusammen unter 15 % der gelesenen Artikel im Fenster
  ausmachen: " — am Wochenende bleibt der Reader meist zu."
- Bei zu wenig Daten (weniger als 10 gelesene Artikel im 91-Tage-Fenster) wird der Satz nicht
  angezeigt (leerer Platz statt eines aus Rauschen abgeleiteten, irreführenden Satzes).

## Bug-Fix: Lesezeit wird tatsächlich gespeichert

`ArticleStore.upsert()` unterstützt `estimatedReadingMinutes` bereits vollständig (INSERT und
UPDATE) — der Fehler liegt ausschließlich an den beiden Aufrufstellen, die den Parameter nie
befüllen. Fix:

1. Neue öffentliche Funktion `ReaderMetadataFormatter.estimatedMinutes(content: String?,
   summary: String?) -> Int?`, extrahiert aus der bestehenden `readingTimeText`-Logik (200
   Wörter/Minute, `nil` bei leerem Text) — eine einzige Quelle der Wahrheit für Reader-Anzeige
   **und** persistierten Wert, keine Duplikation.
2. `SQLiteFeedRefreshService.swift:136` und `SQLiteFeedSubscriptionService.swift:171`: beim
   Bau von `ArticleUpsertInput` zusätzlich
   `estimatedReadingMinutes: ReaderMetadataFormatter.estimatedMinutes(content:
   article.content, summary: article.summary)` übergeben.
3. **Rückwirkender Backfill** (Nutzerentscheidung — "Gesamte Lesezeit" soll sofort stimmen,
   nicht erst nach Wochen erneuten Abrufs): neue Migration
   `v30_backfill_article_estimated_reading_minutes`, analog zum bestehenden
   `syncStableID`-Backfill-Muster (Migration v26) — Swift-Loop über alle `articles`-Zeilen mit
   `estimatedReadingMinutes IS NULL`, Wert über dieselbe `ReaderMetadataFormatter`-Funktion
   berechnen, per Batch-`UPDATE` schreiben (SQLite hat keine Wortzähl-Funktion, muss in Swift
   passieren — wie bei v26 dokumentiert).

## Datenschicht (`StatisticsStore`)

- `readingStatistics(range:)` bleibt der zentrale Einstiegspunkt, liefert zusätzlich:
  - `weekdayCounts` / `daypartCounts`: Aggregation über das feste 91-Tage-Fenster
    (`heatmapStart`, bereits vorhanden). **Wichtig:** Bucketing (Wochentag, Tagesabschnitt)
    läuft in Swift über `Calendar.current`/`TimeZone.current` auf den rohen `readAt`-Werten,
    nicht über SQLite-`strftime`/`date()` — SQLite-Datumsfunktionen arbeiten auf dem
    gespeicherten (UTC-)Zeitstempel, was Wochentag/Uhrzeit für Nutzer außerhalb UTC verzerren
    würde. Aus demselben Grund wird **die bestehende `dailyReadCounts`-Query für die Heatmap
    im selben Zug auf dieselbe Swift-seitige Tageszuordnung umgestellt** (bisher rohes SQL
    `date(readAt)` — betrifft denselben latenten Zeitzonen-Fehler, wird hier mitkorrigiert, da
    wir ohnehin an derselben Stelle arbeiten).
  - `topFeedsByTime` / `topTagsByTime`: wie bisherige `topFeeds`/`topTags`-Queries, aber
    `SUM(a.estimatedReadingMinutes)` statt `COUNT(*)` als Sortier-/Anzeigewert (Tiebreak bei
    Gleichstand: Titel alphabetisch, `COLLATE NOCASE` — dieselbe Konvention wie die
    bestehende `count DESC, f.title COLLATE NOCASE`-Sortierung), Artikelanzahl bleibt als
    Sekundärinfo erhalten.
  - `feedHealthCandidates`: neue, eigenständige Aggregatabfrage über alle Feeds (all-time,
    kein `range`-Parameter) — `HAVING COUNT(*) >= 20 ORDER BY (gelesen*1.0/gesamt) ASC,
    f.title COLLATE NOCASE LIMIT 5` (derselbe Tiebreak). Ersetzt die bisherige
    N+1-Schleife in `StatisticsWindowView.loadStatistics()`
    (`feeds.map { statisticsStore.feedReadingStatistics(feedID: feed.id) }`) für die
    Fenster-Anzeige durch eine einzelne Abfrage — die bestehende
    `feedReadingStatistics(feedID:)`-Methode bleibt für den CSV-Export unverändert bestehen.
- Bestehende Felder (`articlesReadToday/ThisWeek/Total`, `articlesReadInSelectedRange`,
  `articlesReadInPreviousPeriod`, `totalReadingMinutesAllTime`,
  `averageReadingMinutesPerDay`, `currentStreak`, `longestStreak`) bleiben unverändert in
  Bedeutung — durch den Bug-Fix liefern die Lesezeit-Felder erstmals echte Werte.

## Betroffene Dateien (Überblick, keine abschließende Liste)

- `Feedivo/Views/Reader/ReaderMetadataFormatter.swift` — neue `estimatedMinutes(...)`-Funktion
- `Feedivo/Services/SQLiteFeedRefreshService.swift`,
  `Feedivo/Services/SQLiteFeedSubscriptionService.swift` — `ArticleUpsertInput` befüllen
- `Feedivo/Database/FeedivoDatabaseMigrator.swift` — neue Migration v30
- `Feedivo/Stores/StatisticsStore.swift` — neue/geänderte Queries wie oben beschrieben
- `Feedivo/Snapshots/ReadingStatisticsSnapshot.swift` — neue Felder
  (`weekdayCounts`/`daypartCounts`/`topFeedsByTime`/`topTagsByTime`/`feedHealthCandidates`),
  `topFeeds`/`topTags` entfallen zugunsten der `...ByTime`-Varianten
- `Feedivo/Views/Statistics/StatisticsWindowView.swift` — Layout-Umbau wie oben
- `Feedivo/Views/Statistics/StatisticsHeatmapView.swift` — Zellgröße/Einbettung anpassen
- `Feedivo/Services/StatisticsExportService.swift` — liest aktuell direkt
  `readingStatistics.topFeeds`/`.topTags` (Anzahl-basiert) für die CSV-Abschnitte
  "Meistgelesene Feeds"/"Meistgenutzte Tags" — muss auf `topFeedsByTime`/`topTagsByTime`
  umgestellt werden, da die Anzahl-Felder entfallen. Die `...ByTime`-Einträge enthalten
  bereits sowohl Artikelanzahl als auch Minuten (siehe oben), die CSV-Spalte "Anzahl" wird
  dadurch natürlich um eine "Lesezeit (Minuten)"-Spalte ergänzt statt ersetzt — kein
  Informationsverlust, eher eine Verbesserung (echte Lesezeit statt der bisherigen,
  ohnehin immer-0-Werte an anderer Stelle im Export)
- Neue kleine Teilansichten unter `Feedivo/Views/Statistics/` (z. B.
  `StatisticsWeekdayBarsView`, `StatisticsDaypartBarsView`, `StatisticsRankListView`,
  `StatisticsFeedHealthListView`) statt alles in einer wachsenden `StatisticsWindowView.swift`
  unterzubringen
- Neue L10n-Keys für Abschnittstitel/-untertitel, Tagesabschnitte, Erkenntnis-Satz,
  Feed-Gesundheit-Texte

## Testing

- `ReaderMetadataFormatter.estimatedMinutes(...)`: leerer Text → `nil`, kurzer/langer Text →
  korrekte Minutenzahl (200 Wörter/Minute, Minimum 1), Fallback content→summary.
- Migration v30: Bestandszeilen mit `NULL` werden befüllt, bereits gesetzte Werte bleiben
  unangetastet (Idempotenz bei erneutem Migrationslauf über GRDBs Migrationsmechanismus
  ohnehin gegeben, aber der Backfill-Filter `WHERE estimatedReadingMinutes IS NULL` wird
  explizit mitgetestet).
- `StatisticsStore`: neue Aggregationen (`weekdayCounts`, `daypartCounts`, `topFeedsByTime`,
  `topTagsByTime`, `feedHealthCandidates`) je mit Fixture-Daten über Zeitzonen-Grenzen hinweg
  (mindestens ein Test mit einer Nicht-UTC-`TimeZone.current`, um die Swift-seitige
  Tages-/Wochentag-Zuordnung gegen die alte SQL-`date()`-Zuordnung abzusichern),
  Mindest-Artikelzahl-Filter bei Feed-Gesundheit, Sortierreihenfolge.
- Erkenntnis-Satz-Formatierung: Basissatz, Wochenend-Zusatz-Schwelle (15 %), Datenmangel-Fall
  (< 10 Artikel → kein Satz).
- Feed-Gesundheit-Löschung: bestehender Bestätigungsdialog-Flow, Liste aktualisiert sich nach
  erfolgreichem Löschen.
- Manuelle Live-Verifikation (kein computer-use für native macOS-Apps verfügbar): Hero-Layout
  in Hell-/Dunkelmodus, Heatmap-Zellgröße wirkt wie im abgestimmten Mockup, Erkenntnis-Satz
  bei echten Nutzerdaten plausibel, "Abbestellen" löscht tatsächlich den Feed inkl.
  Bestätigungsdialog, CSV-Export weiterhin fehlerfrei (jetzt mit echten Lesezeit-Werten).

## Out of Scope

- Der CSV-Export wird nur mechanisch an die umbenannten Felder angepasst (siehe
  „Betroffene Dateien"), nicht inhaltlich neu gestaltet — eine Erweiterung um die neuen
  Abschnitte (Gewohnheiten, Feed-Gesundheit) als eigene CSV-Tabellen ist ein möglicher
  späterer, eigener Schritt.
- Keine Änderung an der grundsätzlichen Heatmap-Bucket-Logik (Quartils-Stufen 0–4) — nur
  Zellgröße/Einbettung und die Zeitzonen-Korrektur der Tageszuordnung.
- Keine Historisierung/kein Trend über mehrere 91-Tage-Fenster hinweg (z. B. "Vormonat vs.
  Vergleich") — Gewohnheiten/Feed-Gesundheit zeigen immer den aktuellen Stand, keinen
  Verlauf.
- Keine KI-/Freitext-Generierung des Erkenntnis-Satzes — rein regelbasiert wie oben
  beschrieben.
