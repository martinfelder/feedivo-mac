# Handoff: OPML-Export Dialog

## Overview
Ein modaler Dialog zum Exportieren von RSS-Feed-Abonnements als OPML-Datei. Der Nutzer wählt aus, welche Daten (Ordnerstruktur, Tags, Beschreibungen) mit exportiert werden, sieht eine Live-Zusammenfassung des Exports und bestätigt mit „Sichern…". Teil der Feedivo-App (RSS-Reader, macOS-nativer Stil).

## About the Design Files
Die Dateien in diesem Paket (`OPML-Export Dialog.dc.html`, `support.js`) sind **Design-Referenzen, erstellt in HTML** — ein Prototyp, der Aussehen und Verhalten zeigt, **kein produktiver Code zum direkten Kopieren**. `support.js` ist nur die Laufzeit für die Prototyp-Vorschau und gehört **nicht** in die Zielanwendung.

Aufgabe: Dieses Design in der **bestehenden Umgebung des Ziel-Codebases** nachbauen (React, Vue, SwiftUI, native o. ä.) mit dessen etablierten Mustern und Bibliotheken. Falls noch keine Umgebung existiert, das passendste Framework wählen und dort umsetzen.

## Fidelity
**High-fidelity (hifi)**: Pixel-genaue Mockups mit finalen Farben, Typografie, Abständen und Interaktionen. Die UI sollte pixelgenau mit den vorhandenen Bibliotheken/Mustern des Codebases nachgebaut werden. Der Dialog folgt demselben Design-System wie die übrigen Feedivo-Screens (Verwaltung, Regel-Dialog): macOS-nativer Look, Systemschrift, Akzentfarbe `#0A84FF`.

## Screens / Views

### View: OPML-Export Dialog
- **Name**: OPML exportieren
- **Purpose**: Nutzer konfiguriert und startet den Export seiner Feed-Abonnements als OPML-Datei.
- **Layout**:
  - Zentrierter modaler Container über abgedunkeltem Hintergrund (`backdrop`).
  - Dialog: `max-width: 660px`, volle Breite, `background: #FFFFFF`, `border-radius: 13px`, `box-shadow: 0 24px 70px rgba(0,0,0,.20), 0 0 0 0.5px rgba(0,0,0,.10)`, `overflow: hidden`.
  - Vertikale Struktur: **Header** → 1px-Trennlinie → **Body** → 1px-Trennlinie → **Footer**.
  - Body ist ein `display: grid` mit `grid-template-columns: 1fr 1fr; gap: 20px`. Links die Optionen, rechts die Zusammenfassung.

- **Components**:

  **Header** (`padding: 24px 26px 20px`, Flex row, space-between, align-items flex-start, gap 18px)
  - Titel „OPML exportieren": `font-size: 21px; font-weight: 700; letter-spacing: -0.3px; color: #1D1D1F`.
  - Untertitel: „Erstelle eine OPML-Datei mit deinen Feed-Abonnements. Die Datei kann später wieder in Feedivo oder andere RSS-Reader importiert werden." `font-size: 13.5px; color: #86868B; line-height: 1.5; margin-top: 5px; max-width: 430px`.
  - Badge „73 Feeds" (rechts, flex:none): Pille `border-radius: 999px; padding: 5px 11px; background: rgba(52,199,89,.14); color: #2FA84F; font-size: 12.5px; font-weight: 700; white-space: nowrap`.

  **Options-Spalte** (links) — vertikale Liste von 4 Zeilen. Jede Zeile: `display:flex; align-items:flex-start; gap:13px; padding:14px 0`, ab der zweiten Zeile `border-top: 1px solid rgba(0,0,0,.10)`.
  - Checkbox (Button): `20×20px; border-radius: 6px; margin-top: 1px`.
    - Aktiv/checked: `background: #0A84FF; border: 1px solid #0A84FF; box-shadow: 0 1px 2px rgba(10,132,255,.35)`, weißes Häkchen „✓" (`font-size: 11px; font-weight: 800; color: #fff`).
    - Inaktiv: `background: #FFFFFF; border: 1px solid rgba(0,0,0,.10); box-shadow: 0 1px 1px rgba(0,0,0,.04)`.
    - Gesperrt (nur erste Option, immer an): `background: rgba(10,132,255,.4)` (`#0A84FF` @ 66 hex alpha); `border: 1px solid transparent`; `cursor: default`; kein Shadow; Häkchen sichtbar aber gedämpft. Kein Toggle möglich.
  - Titel der Option: `font-size: 14px; font-weight: 700; letter-spacing: -0.1px`.
  - Beschreibung: `font-size: 12.5px; color: #86868B; line-height: 1.45; margin-top: 3px`.
  - Die 4 Optionen (Titel · Beschreibung · Default):
    1. **Feed-URLs und Titel** · „Immer enthalten. Das ist die Grundlage jeder OPML-Datei." · checked + **gesperrt**.
    2. **Ordner-Struktur einschließen** · „Feeds werden in OPML-Gruppen exportiert, damit deine Sidebar-Struktur erhalten bleibt." · checked.
    3. **Tags einschließen** · „Feed-Tags werden als Kategorie-Attribut mitgeschrieben." · checked.
    4. **Feed-Beschreibungen einschließen** · „Optional für Reader, die Feed-Metadaten beim Import übernehmen." · unchecked.

  **Zusammenfassung-Card** (rechts, `align-self: start`): `background: #F5F5F7; border: 1px solid rgba(0,0,0,.10); border-radius: 12px; padding: 16px 17px`.
  - Überschrift „Zusammenfassung": `font-size: 14px; font-weight: 700; letter-spacing: -0.1px`.
  - Zeilenliste (`margin-top: 12px`), jede Zeile: `display:flex; justify-content:space-between; align-items:center; gap:12px; padding:7px 0`, ab der zweiten `border-top: 1px solid rgba(0,0,0,.10)`.
    - Label: `font-size: 13px; color: #86868B`. Wert: `font-size: 13px; font-weight: 700; font-variant-numeric: tabular-nums; color: #1D1D1F`.
    - Zeilen (Label → Wert): Feeds → `73` · Ordner → `18 Ordner` · Tags → `0 Tags` · Beschreibungen → `Aus`.
  - Dateiname-Chip (`margin-top: 14px`): `padding: 10px 12px; background: #FFFFFF; border: 1px solid rgba(0,0,0,.10); border-radius: 8px; font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 12.5px; color: #86868B; word-break: break-all`. Inhalt: `Feedivo-Export-2026-07-08.opml`.

  **Footer** (`padding: 16px 26px`, Flex row, space-between, gap 16px, wrap)
  - Hinweistext links: „Exportiert nur Abonnements, keine Artikel und keine Favoriten." `font-size: 12.5px; color: #86868B`.
  - Button-Gruppe rechts (`gap: 10px`):
    - **Abbrechen** (secondary): `padding: 8px 18px; border-radius: 8px; border: 1px solid rgba(0,0,0,.10); background: #FFFFFF; color: #1D1D1F; font-size: 13px; font-weight: 600; box-shadow: 0 1px 1px rgba(0,0,0,.04)`.
    - **Sichern…** (primary): `padding: 8px 22px; border-radius: 8px; border: none; background: #0A84FF; color: #fff; font-size: 13px; font-weight: 600; box-shadow: 0 1px 3px rgba(10,132,255,.45)`.

## Interactions & Behavior
- **Checkbox-Toggle**: Klick auf eine der drei nicht gesperrten Checkboxen invertiert deren `checked`-Zustand. Die gesperrte Option „Feed-URLs und Titel" reagiert nicht auf Klicks.
- **Live-Zusammenfassung**: Die Werte in der Zusammenfassung folgen dem Optionsstatus:
  - „Ordner-Struktur" an → `Ordner: 18 Ordner`, aus → `Ordner: Aus`.
  - „Tags" an → `Tags: 0 Tags`, aus → `Tags: Aus`.
  - „Beschreibungen" an → `Beschreibungen: Ein`, aus → `Beschreibungen: Aus`.
  - `Feeds: 73` ist konstant.
- **Abbrechen**: schließt den Dialog ohne Export.
- **Sichern…**: löst den Datei-Speicherdialog / OPML-Generierung aus (im Prototyp nicht implementiert).
- Transitions: Checkbox-Zustandswechsel `transition: all .12s`.
- Keine expliziten Hover-States im Prototyp definiert — im Codebase die üblichen Hover-Feedbacks für Buttons/Checkboxen ergänzen.

## State Management
- `options`: Array von `{ id, title, desc, checked, locked }`. Steuert Checkbox-Zustand.
  - `urls` (locked, checked), `folders` (checked), `tags` (checked), `desc` (unchecked).
- Abgeleitete Werte für die Zusammenfassung werden aus dem `checked`-Status der Optionen berechnet (kein separater State).
- Realdaten, die im echten System angebunden werden müssen: Anzahl Feeds (73), Anzahl Ordner (18), Anzahl Tags (0), generierter Dateiname (`Feedivo-Export-<YYYY-MM-DD>.opml`).

## Design Tokens

### Colors — Light (Default)
- Dialog-Hintergrund `--bg`: `#FFFFFF`
- Card `--card`: `#F5F5F7`
- Card2 / Inputs `--card2` / `--input`: `#FFFFFF`
- Text `--text`: `#1D1D1F`
- Text sekundär `--text2`: `#86868B`
- Border `--border`: `rgba(0,0,0,0.10)`
- Akzent `--accent`: `#0A84FF`
- Shadow `--shadow`: `rgba(0,0,0,0.20)`
- Backdrop `--backdrop`: `#E7E7EA`
- Erfolg / grüne Pille: Text `#2FA84F`, Hintergrund `rgba(52,199,89,.14)`

### Colors — Dark
- `--bg`: `#28282B` · `--card`: `#323235` · `--card2`: `#3A3A3D` · `--text`: `#F5F5F7` · `--text2`: `#9A9AA0` · `--border`: `rgba(255,255,255,0.12)` · `--accent`: `#0A84FF` · `--input`: `#1F1F22` · `--shadow`: `rgba(0,0,0,0.55)` · `--backdrop`: `#161618`

### Typography
- Font-Stack: `-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif`, `-webkit-font-smoothing: antialiased`
- Monospace (Dateiname): `ui-monospace, 'SF Mono', Menlo, monospace`
- Skala: Titel 21/700, Card-Überschrift & Optionstitel 14/700, Untertitel 13.5/400, Body/Labels 13/13.5, Beschreibungen 12.5, Badge/Chip 12.5

### Spacing
- Dialog-Padding Header `24px 26px 20px`, Body `22px 26px`, Footer `16px 26px`
- Grid-Gap Body `20px`, Optionszeilen `14px 0`, Card-Padding `16px 17px`

### Border Radius
- Dialog `13px` · Cards `12px` · Buttons/Inputs/Chip `8px` · Checkbox `6px` · Pille/Badge `999px`

### Shadows
- Dialog: `0 24px 70px rgba(0,0,0,.20), 0 0 0 0.5px rgba(0,0,0,.10)`
- Primary-Button: `0 1px 3px rgba(10,132,255,.45)`
- Secondary-Button: `0 1px 1px rgba(0,0,0,.04)`
- Checkbox aktiv: `0 1px 2px rgba(10,132,255,.35)`

## Assets
Keine Bild- oder Icon-Assets. Das Häkchen ist ein Unicode-Zeichen „✓". Alle Farben und Formen sind CSS.

## Files
- `OPML-Export Dialog.dc.html` — der Prototyp (Markup im `<x-dc>`-Template, Logik in der `Component`-Klasse am Dateiende). Enthält Light- und Dark-Theme über die `theme`-Prop.
- `support.js` — nur Vorschau-Laufzeit; **nicht** in die Zielanwendung übernehmen.
