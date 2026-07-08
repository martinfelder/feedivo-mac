# Claude-Code-Prompt: Regel-Dialog „Konzept A" (Karten-Layout)

> Kopiere alles ab der Trennlinie in Claude Code. Die Datei `RuleDialogCards.dc.html`
> in diesem Ordner ist die **verbindliche visuelle Referenz (source of truth)**.
> Bei jedem Zweifel gilt die Datei, nicht deine Interpretation.

---

## Aufgabe

Implementiere den Regel-Erstellen-Dialog exakt nach der folgenden Spezifikation in der bestehenden macOS-App (Feedivo, RSS-Reader). Nutze den vorhandenen Stack der App (SwiftUI oder AppKit bzw. das vorhandene UI-Framework) und die etablierten Muster der Codebase. **Übernimm alle Zahlenwerte, Farben, Abstände und Texte 1:1.** Weiche in **nichts** ab — keine eigenen Design-Entscheidungen, keine „Verbesserungen", keine zusätzlichen Elemente. Die beiliegende Datei `RuleDialogCards.dc.html` ist der maßgebliche Referenz-Prototyp; öffne sie und gleiche das Ergebnis Pixel für Pixel ab.

Der Dialog ist ein modaler Sheet/Fenster-Dialog. Zwei Modi (**Einfach** / **Power User**) und **Light + Dark Mode** müssen unterstützt werden.

---

## 1. Design-Tokens (exakt)

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
- Switch „an": `#34C759`
- WENN-Badge: Text `accent` (`#0A84FF`), Hintergrund `rgba(10,132,255,0.14)`
- DANN-Badge: Text `#2FA84F`, Hintergrund `rgba(52,199,89,0.16)`
- Vorschau-Pille: Text `accent`, Hintergrund `rgba(10,132,255,0.09)`
- Speichern-Button-Schatten: `0 1px 3px rgba(10,132,255,0.45)`

### Tag-Farben (Beispiel-Tags)
| Tag | Farbe |
|---|---|
| Heise+ | `#14B8A6` |
| Wichtig | `#FF453A` |
| Apple | `#0A84FF` |
| Später lesen | `#FF9F0A` |
| Games | `#BF5AF2` |

### Farb-Swatches beim Tag-Erstellen (Reihenfolge exakt)
`#0A84FF`, `#30D158`, `#FF9F0A`, `#FF453A`, `#BF5AF2`, `#14B8A6`, `#64748B`

### Typografie
- Schriftfamilie: System-Font (`-apple-system` / SF Pro Text). `-webkit-font-smoothing: antialiased`.
- Titel „Regel erstellen": **21px / 700**, `letter-spacing: -0.3px`
- Untertitel: **13.5px / 400**, Farbe `text2`
- Abschnitts-Label („NAME", „ZIEL-TAG"): **11px / 700**, `text-transform: uppercase`, `letter-spacing: 0.5px`, Farbe `text2`
- WENN/DANN-Badge: **11px / 800**, `letter-spacing: 0.6px`
- Karten-Beschreibungstext: **13px / 400**, Farbe `text2`
- Segmented-Control-Labels: **13px**, aktiv 600 / inaktiv 500
- Tag-Chips: **13px**, ausgewählt 600 / nicht 500
- Name-Input: **14px**; Bedingungs-Selects/Input: **13px**
- Footer-Buttons: **13px / 600**
- Vorschau-Pille: **12.5px / 600**

### Radien / Schatten / Maße
- Dialog: `max-width: 600px`, `border-radius: 13px`, `padding: 26px 28px 20px`, Schatten `0 24px 70px {shadow}, 0 0 0 0.5px {border}`
- Backdrop: `padding: 34px`, Inhalt zentriert (flex center)
- Karten (WENN/DANN): `border-radius: 11px`, `padding: 15px 16px`, `border: 1px solid {border}`, Hintergrund `card`
- Divider: `height: 1px`, Farbe `border`, `margin: 18px 0`
- Text-Inputs: `border-radius: 8px`, `border: 1px solid {border}`, Hintergrund `input`, Box-Shadow `0 1px 1px rgba(0,0,0,0.04)`; Name-Padding `9px 12px`, Wert-Input-Padding `8px 11px`
- Selects: `border-radius: 8px`, Padding `8px 26px 8px 11px`, eigener Chevron „▾" absolut rechts (9px vom Rand, 9px groß, Farbe `text2`), native Pfeile ausblenden (`appearance: none`)
- WENN/DANN-Badge: `padding: 3px 9px`, `border-radius: 6px`
- Vorschau-Pille: `padding: 8px 12px`, `border-radius: 8px`, `width: fit-content`
- Footer „Abbrechen": `padding: 8px 16px`, `border-radius: 8px`, `border: 1px solid {border}`, Hintergrund `card2`, Schatten `0 1px 1px rgba(0,0,0,0.04)`
- Footer „Speichern": `padding: 8px 20px`, `border-radius: 8px`, keine Border, Hintergrund `accent`, Text `#fff`

### Segmented Control (macOS-Stil, weiße Pille)
- Schiene: Hintergrund `track`, `gap: 2px`, `padding: 2px`, `border-radius: 8px` (Aktion: 9px)
- Segment: `border-radius: 6px`, keine Border
- Modus-Segment-Padding: `5px 15px`. Aktions-Segmente: `flex: 1`, zentriert, Padding `7px 6px`
- **Aktiv**: Hintergrund `pill`, Text `text`, `font-weight: 600`, Schatten `0 1px 2px rgba(0,0,0,0.14), 0 0 0 0.5px rgba(0,0,0,0.05)`
- **Inaktiv**: Hintergrund transparent, Text `text2`, `font-weight: 500`
- Übergang: `all 0.15s`

### Switch (Aktiv-Toggle)
- Schiene: `38 × 23px`, `border-radius: 12px`; an = `#34C759`, aus = `track`
- Knopf: `19 × 19px`, weiß, `border-radius: 50%`, `top: 2px; left: 2px`, Schatten `0 1px 2px rgba(0,0,0,0.3)`
- An = `translateX(15px)`, aus = `translateX(0)`; Übergang `0.2s`

---

## 2. Aufbau (von oben nach unten, exakte Reihenfolge)

1. **Titel** „Regel erstellen"
2. **Untertitel** „Lege fest, was Feedivo automatisch mit passenden Artikeln macht."
3. **Zeile Modus/Aktiv** (`space-between`):
   - Links: Label „Modus" (13px, text2) + Segmented `[ Einfach | Power User ]`
   - Rechts: Label „Aktiv" (13px, text) + Switch
4. **Divider**
5. **Label „NAME"** + Text-Input (voll breit), Placeholder „Regel benennen…"
6. **WENN-Karte**:
   - Kopf: Badge **„WENN"** + Text „Ein Artikel diese Bedingungen erfüllt"
   - *(nur Power User)* Zeile: „Treffer bei" + Segmented `[ Alle Bedingungen | Eine reicht ]`
   - **Bedingungszeile(n)**, je Zeile in `flex`, `gap: 8px`, umbrechend:
     - Select **Feld** (`flex: 1 1 120px`, min 110px)
     - Select **Operator** (`flex: 1 1 120px`, min 110px)
     - Input **Wert** (`flex: 2 1 160px`, min 130px), Placeholder „Suchbegriff…"
     - *(nur Power User & >1 Bedingung)* Entfernen-Button „×": `28×28px`, `border-radius: 8px`, Border `1px {border}`, Hintergrund `card2`, Farbe `text2`
   - *(nur Power User)* Button „**+ Bedingung hinzufügen**": `padding: 7px 12px`, `border-radius: 8px`, gestrichelte Border `1px dashed {border}`, transparent, Text `accent`, 12.5px/600
   - **Vorschau-Pille**: kleiner Ziel-Ring (14px Kreis, 2px Border `accent`, innen 3px Punkt `accent`) + Text „**1 Artikel passt**" (nicht umbrechen)
7. **Verbinder**: zentriertes „▾" (13px, `text2`, `margin: 5px 0`)
8. **DANN-Karte**:
   - Kopf: Badge **„DANN"** + Text „Wird automatisch ausgeführt"
   - **Aktions-Segmented (voll breit, 3 gleiche)**: `[ Tag zuweisen | Artikel ausblenden | Benachrichtigen ]`
   - **Wenn Aktion = „Tag zuweisen"**:
     - Label „ZIEL-TAG"
     - **Tag-Chips** (umbrechend, `gap: 8px`): je Chip farbiger Punkt (9px) + Name; ausgewählt zeigt zusätzlich „✓"
       - Ausgewählt: Border `1.5px solid {tagColor}`, Hintergrund `{tagColor}22` (13 % Alpha), 600
       - Nicht ausgewählt: Border `1px solid {border}`, Hintergrund `card2`, 500
     - **Chip „+ Neu"**: gestrichelte Border, Farbe `text2`, 600
     - **Tag-Erstellen-Formular** (nur wenn „+ Neu" geklickt): Box `card2`, Border, `border-radius: 10px`, `padding: 13px`:
       - Text-Input, Placeholder „Tag-Name…"
       - Reihe Farb-Swatches (22px Kreise). Ausgewählter Swatch: Ring `0 0 0 2px {bg}, 0 0 0 4px {farbe}`
       - Rechts: Buttons „Abbrechen" + „Erstellen". „Erstellen" ist **deaktiviert** solange der Name leer ist (dann Hintergrund `track`, Text `text2`, kein Schatten; sonst `accent`/weiß).
   - **Wenn Aktion = „Artikel ausblenden"**: Hinweistext „Passende Artikel werden automatisch ausgeblendet und erscheinen unter **Ausgeblendet**." („Ausgeblendet" in `text`-Farbe, 600)
   - **Wenn Aktion = „Benachrichtigen"**: Hinweistext „Du erhältst eine **macOS-Benachrichtigung**, sobald ein passender Artikel eintrifft." („macOS-Benachrichtigung" in `text`-Farbe, 600)
9. **Footer** (rechtsbündig, `gap: 10px`): Button „Abbrechen", Button „Speichern"

---

## 3. Zustände & Verhalten

State-Variablen (mit Defaults):
- `mode`: `"einfach" | "power"` — Default `"einfach"`
- `active`: Bool — Default `true`
- `matchMode`: `"all" | "any"` — Default `"all"` (nur in Power User sichtbar/relevant)
- `action`: `"tag" | "hide" | "notify"` — Default `"tag"`
- `selectedTag`: Tag-ID — Default `"heiseplus"`
- `creatingTag`: Bool — Default `false`
- `newTagName`: String — Default `""`
- `newTagColor`: Hex — Default `"#0A84FF"`
- `ruleName`: String — Default `"Snapzy: Kostenlose Mac-App fordert CleanShot X und Shottr heraus"`
- `conditions`: Array von `{ field, op, value }` — Default `[{ field: "Titel", op: "enthält", value: "Snapzy" }]`

Modus-Unterschiede:
- **Einfach**: genau **eine** Bedingung; **kein** „Treffer bei"-Segmented, **kein** „+ Bedingung", **kein** „×"-Entfernen.
- **Power User**: mehrere Bedingungen; „Treffer bei"-Segmented sichtbar; „+ Bedingung hinzufügen" fügt `{ field:"Titel", op:"enthält", value:"" }` an; „×" entfernt eine Zeile (nur sichtbar wenn >1 Bedingung).

Auswahllisten (exakt, in dieser Reihenfolge):
- **Feld**: Titel, Beschreibung, Autor, Link, Feed, Kategorie
- **Operator**: enthält, enthält nicht, ist gleich, beginnt mit, endet mit, Regex

Interaktionslogik:
- Tag-Chip klicken → setzt `selectedTag`, schließt ein offenes Erstellen-Formular (`creatingTag = false`).
- „+ Neu" klicken → `creatingTag = true`, `selectedTag = null`.
- „Erstellen" (nur bei nicht-leerem Namen) → neuen Tag mit `newTagName`/`newTagColor` anlegen, ihn auswählen, Formular schließen, `newTagName` leeren.
- „Abbrechen" im Formular → `creatingTag = false`, `newTagName` leeren.
- Aktion wechseln → blendet den passenden Unterbereich ein (Tag-Picker bzw. Hinweistext).

Übergänge (Dauer exakt): Segmente `0.15s`, Switch `0.2s`, Chips `0.12s`, Swatch-Ring `0.12s`.

---

## 4. Akzeptanzkriterien

- Light **und** Dark Mode entsprechen exakt den Token-Tabellen oben.
- Modus-Umschaltung ändert Sichtbarkeit exakt wie beschrieben (Einfach vs. Power User).
- Alle drei Aktionen zeigen den korrekten Unterbereich.
- Tag-Picker: Chips auswählbar, „+ Neu" öffnet Formular, „Erstellen" bleibt deaktiviert bei leerem Namen.
- Kein zusätzliches Element, keine abweichenden Farben/Abstände. Bei Unklarheit → `RuleDialogCards.dc.html` öffnen und exakt nachbauen.
