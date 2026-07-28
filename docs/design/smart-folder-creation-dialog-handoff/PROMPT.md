# Claude-Code-Prompt: Dialog „Intelligenten Ordner erstellen"

> Kopiere alles ab der Trennlinie in Claude Code. Die Datei `SmartFolderDialog.dc.html`
> in diesem Ordner ist die **verbindliche visuelle Referenz (source of truth)**.
> Bei jedem Zweifel gilt die Datei, nicht deine Interpretation.
>
> Das Design nutzt exakt dieselbe Designsprache wie der bereits umgesetzte
> Regel-Dialog „Konzept A" (`RuleDialogCards`). Wenn dieser bereits in der Codebase
> implementiert ist, **verwende dieselben Design-Tokens, Komponenten und Muster wieder.**

---

## Aufgabe

Implementiere den Dialog „Intelligenten Ordner erstellen" exakt nach der folgenden Spezifikation in der bestehenden macOS-App (Feedivo, RSS-Reader). Nutze den vorhandenen Stack der App (SwiftUI oder AppKit bzw. das vorhandene UI-Framework) und die etablierten Muster der Codebase. **Übernimm alle Zahlenwerte, Farben, Abstände und Texte 1:1.** Weiche in **nichts** ab — keine eigenen Design-Entscheidungen, keine „Verbesserungen", keine zusätzlichen Elemente. Die beiliegende Datei `SmartFolderDialog.dc.html` ist der maßgebliche Referenz-Prototyp; öffne sie und gleiche das Ergebnis Pixel für Pixel ab.

Der Dialog ist ein modaler Sheet/Fenster-Dialog. **Light + Dark Mode** müssen unterstützt werden. Die Design-Tokens sind identisch zum Regel-Dialog.

---

## 1. Design-Tokens (exakt — identisch zum Regel-Dialog)

### Farben – Light Mode
| Token | Wert |
|---|---|
| `bg` (Dialog-Hintergrund) | `#FFFFFF` |
| `card` (Karten-Hintergrund) | `#F5F5F7` |
| `card2` (verschachtelt / Buttons) | `#FFFFFF` |
| `text` (Primärtext) | `#1D1D1F` |
| `text2` (Sekundärtext) | `#86868B` |
| `border` | `rgba(0,0,0,0.10)` |
| `accent` | `#0A84FF` |
| `track` (Segmented-Schiene) | `#E9E9EB` |
| `pill` (aktives Segment) | `#FFFFFF` |
| `input` | `#FFFFFF` |
| `shadow` | `rgba(0,0,0,0.20)` |
| `backdrop` (hinter Dialog) | `#E7E7EA` |

### Farben – Dark Mode
| Token | Wert |
|---|---|
| `bg` | `#28282B` |
| `card` | `#323235` |
| `card2` | `#3A3A3D` |
| `text` | `#F5F5F7` |
| `text2` | `#9A9AA0` |
| `border` | `rgba(255,255,255,0.12)` |
| `accent` | `#0A84FF` |
| `track` | `#48484B` |
| `pill` | `#6A6A6E` |
| `input` | `#1F1F22` |
| `shadow` | `rgba(0,0,0,0.55)` |
| `backdrop` | `#161618` |

### Feste Farben (beide Modi identisch)
- Aktive Checkbox: Hintergrund + Border `accent` (`#0A84FF`), Haken weiß, Schatten `0 1px 2px rgba(10,132,255,0.4)`
- Vorschau-Ziel-Ring: `accent`
- Speichern-Button-Schatten: `0 1px 3px rgba(10,132,255,0.45)`

### Ordner-Farben (Farb-Picker, Reihenfolge exakt)
`#0A84FF`, `#14B8A6`, `#FF9F0A`, `#30D158`, `#48484B`, `#BF5AF2`, `#FF453A`, `#FF7A00`

### Typografie
- Schriftfamilie: System-Font (`-apple-system` / SF Pro Text). `-webkit-font-smoothing: antialiased`.
- Titel „Intelligenten Ordner erstellen": **21px / 700**, `letter-spacing: -0.3px`
- Untertitel: **13.5px / 400**, Farbe `text2`
- Abschnitts-Label („NAME", „DARSTELLUNG", „BEDINGUNGEN"): **11px / 700**, `text-transform: uppercase`, `letter-spacing: 0.5px`, Farbe `text2`
- Checkbox-Label „In Sidebar anzeigen": **13.5px**, Farbe `text`
- Inline-Labels „Icon" / „Farbe" / „Operator": **12.5–13px**, Farbe `text2`
- Segmented-Control-Labels: **13px**, aktiv 600 / inaktiv 500
- Name-Input: **14px**; Bedingungs-Selects/Input: **13px**
- Footer-Buttons: **13px / 600**
- Live-Vorschau: Titel **13.5px / 700** (`text`), Zeile **12.5px** (`text2`)

### Radien / Schatten / Maße
- Dialog: `max-width: 640px`, `border-radius: 13px`, `padding: 26px 28px 20px`, Schatten `0 24px 70px {shadow}, 0 0 0 0.5px {border}`
- Backdrop: `padding: 34px`, Inhalt zentriert (flex center)
- Divider: `height: 1px`, Farbe `border`, `margin: 18px 0`
- Karten (Darstellung, Live-Vorschau): `border-radius: 11px`, `border: 1px solid {border}`, Hintergrund `card`; Darstellung-Padding `15px 16px`, Live-Vorschau-Padding `13px 15px`
- Text-Inputs: `border-radius: 8px`, `border: 1px solid {border}`, Hintergrund `input`, Box-Shadow `0 1px 1px rgba(0,0,0,0.04)`; Name-Padding `9px 12px`, Wert-Input-Padding `8px 11px`
- Selects: `border-radius: 8px`, Padding `8px 26px 8px 11px`, eigener Chevron „▾" absolut rechts (9px vom Rand, 9px groß, Farbe `text2`), native Pfeile ausblenden (`appearance: none`)
- Checkbox: `18 × 18px`, `border-radius: 5px`
- Footer „Abbrechen": `padding: 8px 16px`, `border-radius: 8px`, `border: 1px solid {border}`, Hintergrund `card2`, Schatten `0 1px 1px rgba(0,0,0,0.04)`
- Footer „Speichern": `padding: 8px 20px`, `border-radius: 8px`, keine Border, Hintergrund `accent`, Text `#fff`

### Icon-Preview (großes Feld links in „Darstellung")
- `54 × 54px`, `border-radius: 11px`
- Hintergrund `{ordnerFarbe}22` (13 % Alpha), Border `1px solid {ordnerFarbe}55` (33 % Alpha), Icon-Farbe = `{ordnerFarbe}`
- Icon zentriert, ~26px, Strichstärke 1.5

### Icon-Picker (Segmented-Schiene)
- Schiene: Hintergrund `track`, `gap: 2px`, `padding: 3px`, `border-radius: 9px`
- Icon-Button: `30 × 30px`, `border-radius: 6px`, Icon ~17px, Strichstärke 1.6
- **Aktiv**: Hintergrund `pill`, Icon-Farbe `text`, Schatten `0 1px 2px rgba(0,0,0,0.14), 0 0 0 0.5px rgba(0,0,0,0.05)`
- **Inaktiv**: Hintergrund transparent, Icon-Farbe `text2`
- Reihenfolge der Icons (SF-Symbols-Entsprechung): Posteingang/Tray, gefüllter Kreis, Stern, Kalender, durchgestrichenes Auge, Archiv-Box, Lesezeichen, Tag/Etikett, **Ordner-mit-Zahnrad (Default ausgewählt)**, Dokument-mit-Lupe. → In der App die vorhandenen SF-Symbols nutzen (z. B. `tray`, `circle.fill`, `star`, `calendar`, `eye.slash`, `archivebox`, `bookmark`, `tag`, `folder.badge.gearshape`, `doc.text.magnifyingglass`).

### Farb-Picker (Kreise)
- `26 × 26px`, `border-radius: 50%`, Farben s. o.
- Nicht ausgewählt: dünner Rand `0 0 0 0.5px rgba(0,0,0,0.15)`
- Ausgewählt: Ring `0 0 0 2px {bg}, 0 0 0 4px {farbe}`

### Segmented Control „Operator" (macOS-Stil, weiße Pille)
- Schiene: Hintergrund `track`, `gap: 2px`, `padding: 2px`, `border-radius: 8px`
- Segment: `border-radius: 6px`, keine Border, Padding `5px 15px`
- **Aktiv**: Hintergrund `pill`, Text `text`, `font-weight: 600`, Schatten `0 1px 2px rgba(0,0,0,0.14), 0 0 0 0.5px rgba(0,0,0,0.05)`
- **Inaktiv**: Hintergrund transparent, Text `text2`, `font-weight: 500`
- Übergang: `all 0.15s`

### Checkbox „In Sidebar anzeigen"
- `18 × 18px`, `border-radius: 5px`
- **An**: Hintergrund + Border `accent`, weißer Haken „✓" (11px/800), Schatten `0 1px 2px rgba(10,132,255,0.4)`
- **Aus**: Hintergrund `input`, Border `1px solid {border}`, Schatten `0 1px 1px rgba(0,0,0,0.04)`

### Live-Vorschau-Ziel-Ring
- `20 × 20px` Kreis, Border `2px solid accent`, innen 4px Punkt `accent`
- Vier kleine Fadenkreuz-Striche (oben/unten/links/rechts) in `accent`, je ~3px lang

---

## 2. Aufbau (von oben nach unten, exakte Reihenfolge)

1. **Titel** „Intelligenten Ordner erstellen"
2. **Untertitel** „Dynamische Artikelansicht mit globalem UND/ODER-Operator."
3. **Divider**
4. **Label „NAME"** + Text-Input (voll breit), Placeholder „Ordner benennen…"
5. **Checkbox** „In Sidebar anzeigen" (Default: an)
6. **Karte „DARSTELLUNG"**:
   - Label „DARSTELLUNG"
   - Reihe (`flex`, `gap: 16px`, umbrechend):
     - **Icon-Preview** (54px, in gewählter Ordnerfarbe getönt, zeigt gewähltes Icon groß)
     - Rechte Spalte (2 Zeilen):
       - Zeile „Icon": Label (38px breit) + **Icon-Picker-Schiene** (10 Icons, s. o.)
       - Zeile „Farbe": Label (38px breit) + **8 Farb-Kreise**
7. **Zeile „Operator"**: Label „Operator" (13px, text2) + Segmented `[ Erfülle alle Bedingungen | Erfülle eine Bedingung ]`
8. **Label „BEDINGUNGEN"** + **Bedingungszeile(n)**, je Zeile in `flex`, `gap: 8px`, umbrechend:
   - Select **Feld** (`flex: 1 1 120px`, min 110px)
   - Select **Operator/Vergleich** (`flex: 1 1 110px`, min 100px)
   - Input **Wert** (`flex: 2 1 150px`, min 120px), Placeholder `{Feldname}text` (z. B. „Titeltext"), bei Feld „Datum" → „z. B. letzte 7 Tage"
   - Button „**+**" (hinzufügen): `28×28px`, `border-radius: 8px`, Border `1px {border}`, Hintergrund `card2`, Farbe `text2`
   - Button „**−**" (entfernen): gleiche Maße; deaktiviert (Opacity 0.4, kein Klick) wenn nur **eine** Bedingung existiert
9. **Karte „Live-Vorschau"**: Ziel-Ring + Titel „**Live-Vorschau**" + Zeile „`{count}` Artikel passen aktuell zu diesem intelligenten Ordner."
10. **Footer** (rechtsbündig, `gap: 10px`): Button „Abbrechen", Button „Speichern"

---

## 3. Zustände & Verhalten

State-Variablen (mit Defaults):
- `folderName`: String — Default `""`
- `showInSidebar`: Bool — Default `true`
- `icon`: gewähltes Icon — Default `"folder.badge.gearshape"` (Ordner-mit-Zahnrad)
- `color`: Hex — Default `"#48484B"` (Graphit)
- `operator`: `"all" | "any"` — Default `"all"`
- `conditions`: Array von `{ field, op, value }` — Default `[{ field: "Titel", op: "enthält", value: "" }]`

Auswahllisten (exakt, in dieser Reihenfolge):
- **Feld**: Titel, Beschreibung, Autor, Feed, Kategorie, Datum
- **Vergleich**: enthält, enthält nicht, ist gleich, beginnt mit, endet mit

Interaktionslogik:
- Icon anklicken → setzt `icon`; das große Preview-Feld übernimmt Icon **und** aktuelle Farbe sofort.
- Farbkreis anklicken → setzt `color`; Preview-Tönung, Border und Icon-Farbe aktualisieren sich.
- Checkbox anklicken → toggelt `showInSidebar`.
- Operator-Segment → setzt `operator` (globaler UND-/ODER-Operator über alle Bedingungen).
- „+" → fügt **nach** der aktuellen Zeile `{ field:"Titel", op:"enthält", value:"" }` ein.
- „−" → entfernt die Zeile (nur wenn >1 Bedingung; sonst wirkungslos/deaktiviert).
- **Live-Vorschau-Zahl**: In diesem Prototyp Demo-berechnet; in der App durch die **echte, live gegen die Artikeldatenbank ausgewertete Trefferzahl** ersetzen. Zahl im Format Schweizer Tausendertrennung mit Hochkomma anzeigen (z. B. `5'305`).

Übergänge (Dauer exakt): Segmente `0.15s`, Icon-Buttons/Chips `0.12s`, Checkbox `0.12s`, Swatch-Ring `0.12s`.

---

## 4. Akzeptanzkriterien

- Light **und** Dark Mode entsprechen exakt den Token-Tabellen oben (identisch zum Regel-Dialog).
- Icon- und Farbauswahl aktualisieren das große Preview-Feld sofort (Tönung = `{farbe}22`, Border = `{farbe}55`, Icon-Farbe = `{farbe}`).
- „Operator" schaltet zwischen UND (alle) / ODER (eine) um.
- Bedingungen: „+" fügt eine Zeile ein, „−" entfernt sie; „−" ist bei nur einer Bedingung deaktiviert.
- Live-Vorschau zeigt die (in der App echte) Trefferzahl im Format `5'305`.
- Kein zusätzliches Element, keine abweichenden Farben/Abstände. Bei Unklarheit → `SmartFolderDialog.dc.html` öffnen und exakt nachbauen.
