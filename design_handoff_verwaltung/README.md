# Handoff: Verwaltung (Management) — Feedivo RSS Reader

## Overview
The **Verwaltung** window is the settings/management surface of the Feedivo macOS RSS reader.
It is a single window with a left sidebar (4 sections) and a scrollable content area. The four
sections are **Feeds**, **Tags verwalten**, **Intelligente Ordner** (Smart Folders) and **Regeln** (Rules).
This design replaces the earlier native-macOS management screens with a cleaner, more consistent
look that matches the previously-approved "Version A" dialogs (Regel-Dialog / Intelligenter-Ordner-Dialog).

## About the Design Files
The files in this bundle are **design references created in HTML** — a prototype showing the
intended look and behavior. They are **not** production code to copy directly.
The task is to **recreate this design in the target codebase's existing environment** (the app is a
macOS app — likely SwiftUI/AppKit; if implemented as a web/Electron surface, use its React/Vue
patterns). Reuse the codebase's established components, spacing, and icon set where they exist;
only fall back to the exact values below where the codebase has no equivalent.

- `Verwaltung Prototyp.dc.html` — the full interactive prototype (all 4 sections, live navigation).
- `support.js` — runtime for the prototype only. **Not** part of the design; do not port it.

To run the prototype: open `Verwaltung Prototyp.dc.html` in a browser. Click the sidebar items to
switch sections. There is a `theme` toggle (light/dark) exposed as a prop.

## Fidelity
**High-fidelity (hifi).** Colors, typography, spacing, radii and interactions are final and should be
matched closely. Icons are drawn as inline SVG strokes (1.5–1.7px) — reproduce with the codebase's
own icon library (SF Symbols on macOS: see mapping under Assets).

## Global Layout & Chrome

- **Window**: max-width 1040px, height 748px, `border-radius:14px`, `overflow:hidden`.
  Shadow `0 30px 90px rgba(0,0,0,.28)` plus `0 0 0 0.5px` border hairline. Sits on a `#E7E7EA` backdrop.
- **Sidebar**: fixed width **236px**, background `#FAFAFB`, right border `1px rgba(0,0,0,.10)`.
  - Top row (padding `16px 18px 6px`): three traffic-light dots (12px, `#FF5F57` / `#FEBC2E` / `#28C840`) on the left; a sidebar-toggle icon (color `#86868B`) on the right.
  - Nav list (padding `14px 12px`, gap 3px). Each item: `display:flex; gap:11px; padding:8px 12px; border-radius:8px; font-size:14px`.
    - **Inactive**: transparent background, text `#1D1D1F`, weight 500.
    - **Active**: background `#0A84FF`, text/icon `#fff`, weight 600, shadow `0 1px 2px rgba(10,132,255,.4)`.
- **Main area**: flex column.
  - **Toolbar** (height 52px, padding `0 26px`, bottom border hairline): title **"Verwaltung"**, 15px / weight 600 / letter-spacing -0.2px.
  - **Scroll content** (padding `30px 34px 40px`, `overflow-y:auto`). Custom scrollbar: 11px, thumb `rgba(0,0,0,.22)` radius 6 with 3px transparent padding-box border.

Every section starts with a header block:
- Big title: **23px / weight 700 / letter-spacing -0.4px**.
- Subtitle: **13.5px, color `#86868B`**, margin-top 4px.

## Screens / Views

### 1. Feeds
- **Purpose**: search, select, manage and delete RSS feeds.
- **Header**: "Feeds" / "Feeds suchen, auswählen, verwalten und löschen."
- **Toolbar row** (margin-top 22px, flex, gap 10px, wrap):
  - Search input `Feeds suchen` — flex `1 1 260px`, padding `9px 12px`, radius 8, 1px border, bg white, 13.5px.
  - **Alle sichtbaren auswählen** — secondary button.
  - **Auswahl aufheben** — secondary button; opacity 0.45 + not-clickable when nothing selected.
  - **OPML exportieren…** — secondary button.
  - **Auswahl löschen** — destructive button. When ≥1 selected: label becomes `Auswahl löschen (N)`, border `rgba(255,69,58,.35)`, bg `rgba(255,69,58,.10)`, text `#D70015`, trash icon. When none selected: neutral/disabled (opacity 0.55).
- **Feed list**: one bordered rounded container (`1px border`, `radius 12`). Each row:
  - padding `14px 18px`, top hairline between rows. Selected row bg `rgba(10,132,255,.05)`.
  - **Left**: square checkbox (see Design Tokens → Checkbox), margin-top 2px.
  - **Middle** (flex:1): title **14.5px/700**, URL **12.5px color `#5A5A5F`** (word-break), meta **12px color `#86868B`** (e.g. `69 Artikel letzte 7 Tage · Zuletzt aktualisiert: 8. Juli 2026, 10:37`).
  - **Right**: per-row trash icon-button ("Feed löschen").
- **Behavior**: search filters by title or URL (case-insensitive). "Alle sichtbaren auswählen" selects all currently-filtered rows. Row trash deletes that feed; "Auswahl löschen" deletes all selected.

### 2. Tags verwalten
- **Purpose**: rename tags, set their color, delete them, add new tags.
- **Header**: "Tags verwalten" / "Tags umbenennen, farblich markieren oder löschen."
- **"Neuer Tag" block** (uppercase label 11px/700, letter-spacing 0.5px, color `#86868B`):
  - Row: name input (`Tag-Name`, flex `0 1 300px`), a row of 7 color swatches (24px circles, gap 9px), and **Hinzufügen** button.
  - Hinzufügen is `#0A84FF`; disabled state uses `#0A84FF` at ~40% (`#0A84FF66`) while name is empty.
- **Tag rows** (margin-top 26px, gap 12px). Each row: 14px color dot, name input (editable, flex `0 1 300px`), 7-swatch color picker (selected swatch has ring), trash icon-button.
- **Seed data**: one tag — `Heise+`, color `#14B8A6`.

### 3. Intelligente Ordner (Smart Folders)
- **Purpose**: manage sidebar order, visibility and conditions of dynamic folders.
- **Header**: "Intelligente Ordner" / "Reihenfolge, Sichtbarkeit und Bedingungen der Seitenleisten-Ordner verwalten."
- **Sub-header row** (space-between, wrap): left = "Intelligente Ordner" (15px/700) + helper text ("Dynamische Ordner werden in der Sidebar angezeigt und filtern Artikel automatisch."). Right = **Standardordner wiederherstellen** (secondary, with restore/refresh icon) + **Neuer Ordner** (primary blue, leading `+`).
- **Table** (bordered rounded container). Grid columns: `58px 66px minmax(160px,1.1fr) minmax(180px,1.4fr) 74px 70px`, gap 14px.
  - **Header row**: bg `#F5F5F7`, uppercase 11px/700 labels: `Reihenfolge`, `Sidebar`, `Name`, `Bedingungen`, `Treffer` (right-aligned), (blank).
  - **Data rows** (padding `13px 18px`, top hairline): drag handle (`#B8B8BD`, grab cursor) · sidebar checkbox · icon + Name(14px/700) + type(11.5px `#86868B`) · condition text (12.5px `#86868B`, line-height 1.45, may be two lines via `white-space:pre-line`) · Treffer count (13.5px, tabular-nums, right) · edit + trash icon buttons.
- **Seed rows** (name · type · condition · count · icon):
  1. Alle Artikel · Standardordner · `Alle Artikel` · 2’750 · folder-gear
  2. Ungelesen · Standardordner · `Status ist gleich "ungelesen"` · 243 · folder
  3. Mit Stern · Standardordner · `Status ist gleich "mit Stern"` · 12 · star **(color `#FF9F0A`)**
  4. Heute · Standardordner · `Datum ist gleich "heute"` · 99 · calendar
  5. Ausgeblendet · Standardordner · `Status ist gleich "ausgeblendet"` · 11 · eye-slash
  6. Archiviert · Standardordner · `Status ist gleich "archiviert"` · 0 · archive
  7. Diese Woche · Standardordner · `Datum ist gleich "diese Woche"` · 735 · calendar
  8. Gespeichert · Standardordner · `Status ist gleich "mit Stern" ODER` / `Status ist gleich "archiviert"` (two lines) · 12 · archive
  9. Heise+ · **Eigener Ordner** · `Kategorie ist gleich "Heise+"` · 24 · folder-gear
  - Non-starred icons use color `#86868B`.

### 4. Regeln (Rules)
- **Purpose**: manage automation rules applied top-to-bottom.
- **Header**: "Regeln" / "Regeln werden von oben nach unten angewendet."
- **Sub-header row**: left = "Regeln" (15px/700) + helper text. Right = **Auf vorhandene Artikel anwenden** (secondary, with play icon) + **Regel erstellen** (primary blue, leading `+`).
- **Table**. Grid columns: `92px 58px minmax(180px,1.3fr) minmax(150px,200px) 74px 70px`, gap 14px.
  - **Header**: `Reihenfolge`, `Aktiv`, `Regel`, `Aktion`, `Treffer` (right), (blank).
  - **Data rows** (padding `14px 18px`): reorder controls (drag handle + up/down chevron icon, `#B8B8BD`) · active checkbox · rule Name(14px/700) + condition subtitle(12px `#86868B`) · **action badge** · Treffer(13.5px tabular-nums, right) · edit + trash buttons.
  - **Action badge variants** (pill, radius 999, 12.5px/600):
    - *Ausblenden*: bg `rgba(255,149,0,.16)`, text `#B25C00`, leading eye-slash icon (14px). Label `Artikel ausblenden`.
    - *Tag*: bg white, `1px` border, text `#1D1D1F`, leading 9px color dot, label = tag name.
- **Seed rows**:
  1. `heise online News Angebot` · `Titel enthält "heise-Angebot"` · action **Artikel ausblenden** · 22 · active
  2. `heise+ Artikel` · `Titel enthält "heise+"` · action **Heise+** tag (dot `#14B8A6`) · 24 · active

## Interactions & Behavior
- **Sidebar nav**: clicking a section swaps the content area; active item highlighted blue.
- **Feeds**: live search filter; select-all/deselect; per-row + bulk delete (see section 1).
- **Tags**: inline rename (text input), color change via swatch, add (name required), delete.
- **Folders**: sidebar-visibility checkbox toggles per row; delete removes row. Edit and drag-reorder are represented in the UI (edit opens the existing Intelligenter-Ordner dialog; drag reorders) — wire to existing handlers.
- **Rules**: active checkbox toggles per row; delete removes row. Edit opens the existing Regel-Dialog; drag / up-down reorders.
- All transitions are subtle: `transition: all .12s` on interactive fills; checkbox/segment state changes .12–.15s.
- No modal logic is included here — "Neuer Ordner" / "Regel erstellen" / row-edit should open the already-approved Version A dialogs.

## State Management
- `view`: `'feeds' | 'tags' | 'folders' | 'rules'` (active section).
- `feedQuery`: string; `selectedFeeds`: set/map of feed id → bool; `feeds`: array of `{id,title,url,meta}`.
- `tags`: array of `{id,name,color}`; `newTagName`: string; `newTagColor`: hex.
- `folders`: array of `{id,name,type,cond,count,icon,color,sidebar}`.
- `rules`: array of `{id,name,cond,action('hide'|'tag'),tagColor?,tagName?,count,active}`.
- `theme`: `'light' | 'dark'`.

## Design Tokens

### Colors — Light (primary)
- Window bg `#FFFFFF`; sidebar `#FAFAFB`; header/table-header card `#F5F5F7`; card2/white `#FFFFFF`.
- Text `#1D1D1F`; secondary text `#86868B`; tertiary (handles) `#B8B8BD`; URL/link `#5A5A5F`.
- Border/hairline `rgba(0,0,0,0.10)`; segment track `#E9E9EB`.
- Accent (primary/active/selection) `#0A84FF`; selection row tint `rgba(10,132,255,.05)`.
- Destructive text `#D70015`; destructive tint `rgba(255,69,58,.10)`, border `rgba(255,69,58,.35)`.
- Success switch (rules "active" green if using a toggle switch) `#34C759`.
- Backdrop `#E7E7EA`.
- Tag/swatch palette: `#0A84FF`, `#30D158`, `#FF9F0A`, `#FF453A`, `#BF5AF2`, `#14B8A6`, `#64748B`.

### Colors — Dark
- Window `#1E1E20`; sidebar `#2A2A2D`; card `#323235`; card2 `#3A3A3D`.
- Text `#F5F5F7`; secondary `#9A9AA0`; tertiary `#6A6A6E`; link `#6AB0FF`.
- Border `rgba(255,255,255,0.10)`; track `#48484B`; input `#1F1F22`; accent `#0A84FF`; backdrop `#161618`.

### Typography
- Family: `-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif`; `-webkit-font-smoothing: antialiased`.
- Section title 23/700/-0.4; sub-header 15/700; toolbar title 15/600/-0.2.
- Row title 14–14.5/700; body/labels 12.5–13.5; meta 12; uppercase field labels 11/700, letter-spacing 0.4–0.5px.

### Spacing / Radius / Shadow
- Radii: window 14; cards/table containers 12; inputs/buttons/segments 8; checkbox 5; icon buttons 7; pills/chips 999.
- Icon buttons: 30×30, transparent, color `#86868B`.
- Button shadows: secondary `0 1px 1px rgba(0,0,0,.03)`; primary `0 1px 3px rgba(10,132,255,.45)`.
- Content padding `30px 34px 40px`; table header padding `11px 18px`.

### Checkbox (square, used for feed-select, folder-sidebar, rule-active)
- 18×18, radius 5. Unchecked: bg white, `1px` border hairline, shadow `0 1px 1px rgba(0,0,0,.04)`.
- Checked: bg `#0A84FF`, border `#0A84FF`, white check glyph, shadow `0 1px 2px rgba(10,132,255,.35)`.

### Color swatch
- 24×24 circle. Selected = double ring `0 0 0 2px <window-bg>, 0 0 0 4px <color>`; unselected = `0 0 0 0.5px rgba(0,0,0,.18)`.

### Buttons
- **Secondary**: padding `8px 14px`, radius 8, bg `#F5F5F7`, `1px` border, text `#1D1D1F`, 13/600.
- **Primary**: padding `8px 16px`, radius 8, bg `#0A84FF`, text white, 13/600, leading `+` at 15px where shown.

## Assets
All icons are inline stroke SVGs (1.5–1.7px, round caps/joins, 24×24 viewBox). Replace with the app's
icon set. Suggested **SF Symbols** mapping (macOS):
- Feeds nav → `dot.radiowaves.left.and.right` (broadcast)
- Tags nav / tag → `tag`
- Intelligente Ordner nav / folder-gear → `folder.badge.gearshape`
- Regeln nav → `sparkles`
- folder → `folder`; star → `star.fill` (color `#FF9F0A`); calendar → `calendar`;
  eye-slash → `eye.slash`; archive → `archivebox`
- sidebar toggle → `sidebar.left`; trash → `trash`; edit → `pencil`;
  drag handle → `line.3.horizontal`; reorder → `chevron.up.chevron.down`;
  restore → `arrow.clockwise`; apply/play → `play.circle`
No raster/image assets are used.

## Screenshots
Reference renders in `screenshots/` (light theme):
- `01-verwaltung.png` — Feeds
- `02-verwaltung.png` — Tags verwalten
- `03-verwaltung.png` — Intelligente Ordner
- `04-verwaltung.png` — Regeln

## Files
- `Verwaltung Prototyp.dc.html` — full interactive prototype (this is the source of truth).
- Related approved dialogs live in the same project: `RuleDialogCards.dc.html` (Regel-Dialog, Version A) and `Intelligenter-Ordner Dialog.dc.html` — the "Neuer Ordner" / "Regel erstellen" / edit actions should open these.
