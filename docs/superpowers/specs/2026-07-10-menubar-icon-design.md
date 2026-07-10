# Design: Feature 21.1 „Menubar-Icon"

**Datum:** 2026-07-10
**Status:** Genehmigt, bereit für Implementierungsplan

## Kontext

FEATURES.md 21.1 (Status vorher: „✅ Entschieden — bereit zur Implementierung",
keine Vorarbeit im Code):
- Menubar-Icon mit Dropdown (neueste X Artikel + „Feedivo öffnen"-Button)
- Artikelanzahl im Dropdown konfigurierbar
- Schnellaktionen im Dropdown: Refresh, Alle als gelesen markieren
- Badge-Zähler auf dem Menubar-Icon (Anzahl ungelesener Artikel)
- App ohne Dock-Icon betreibbar (Einstellung)
- Klick auf Artikel im Dropdown: in Feedivo öffnen oder im Browser — konfigurierbar

Bestehende Bausteine, die wiederverwendet werden: `AppIconBadgeService`
(Unread-Count-Berechnung aus `FeedSidebarSnapshot`), `FeedViewModel.refreshAllFeeds`,
`ArticleWindowRequest`-Popout-Infrastruktur, `Date.feedivoDisplay(mode:)`,
`ArticleStatusStore`, `SQLiteDataInvalidation.bumpStatusVersion()`.
`Info.plist` ist bereits eine physische Datei (seit Feature 23.2).

## Architektur-Entscheidung

`MenuBarExtra(.window)` (SwiftUI, macOS 13+) statt klassischem
`NSStatusItem`/`NSPopover`. Native, deklarative API, konsistent mit dem
Rest der App (reines SwiftUI, siehe CLAUDE.md-Techstack). Der Dock-Icon-Toggle
läuft über `NSApp.setActivationPolicy(_:)` zur Laufzeit — statisches
`LSUIElement` in Info.plist scheidet aus, weil die Einstellung laut Spec zur
Laufzeit umschaltbar sein muss, ohne Neustart.

## 1. Neue Menubar-Scene

In `FeedivoApp.swift`, als zusätzliche Scene:

```swift
MenuBarExtra(isInserted: $menubarIsEnabled) {
    MenubarDropdownView()
        .environment(\.feedivoDatabase, feedivoDatabase)
} label: {
    MenubarIconLabel(unreadCount: ...)
}
.menuBarExtraStyle(.window)
```

Neue Einstellung `MenubarSettings.isEnabledKey` (Default: **aus** — kein
Verhaltenssprung für Bestandsnutzer, Feature ist rein additiv).

## 2. Dropdown-Inhalt & Schnellaktionen

Neue Datei(en) unter `Feedivo/Views/Menubar/`:

- **`MenubarDropdownView`**: Header („Feedivo öffnen"-Button + Refresh-Button
  mit Spinner während `refreshAllFeeds` läuft), Liste der neuesten *N*
  ungelesenen Artikel (feed-übergreifend, `publishedAt` absteigend sortiert),
  Footer („Alle als gelesen markieren"), Empty State „Keine ungelesenen
  Artikel".
- **Neue Query**: `ArticleStore`/`ArticleDatabase` bekommt eine Methode
  `newestUnread(limit: Int) -> [ArticleListItemSnapshot]` (oder ein neuer,
  schlankerer `MenubarArticleSnapshot`, falls die volle
  `ArticleListItemSnapshot` mehr Felder lädt als nötig — Entscheidung im
  Implementierungsplan anhand der bestehenden Snapshot-Typen).
- **Neue globale Aktion**: `ArticleStatusStore` bekommt `markAllUnreadAsRead()`
  — setzt wirklich alle ungelesenen Artikel app-weit auf gelesen (nicht nur
  die aktuell sichtbaren, im Unterschied zur bestehenden
  `markRowsRead(.allVisible)` in `SQLiteFeedArticleListView`). Ruft danach
  `SQLiteDataInvalidation.bumpStatusVersion()` auf, damit Sidebar-Badges und
  offene Artikellisten sich aktualisieren.

**Artikelanzahl:** `MenubarSettings.articleCountKey`, Default 5, Bereich 3–10
(Stepper, gleiches Muster wie `ArticleListSummaryLineCount` aus Feature 19.1).

## 3. Dock-Icon-Toggle & Artikel-Klick-Verhalten

- `MenubarSettings.hidesDockIconKey` (Default: **aus**). `.onChange` in
  `FeedivoApp.swift` ruft `NSApp.setActivationPolicy(hidesDockIcon ? .accessory : .regular)`.
  Bei `.accessory` bleiben Hauptfenster und Menüleiste (inkl. aller
  bestehenden `.commands`-Shortcuts) voll funktionsfähig, sobald ein Fenster
  fokussiert ist — Standardverhalten von macOS für Accessory-Apps, kein
  Sonderfall nötig.
- `MenubarArticleClickBehavior` (neuer Enum, Cases `.inFeedivo`/`.inBrowser`,
  Default `.inFeedivo`, gleiches `storageKey`/`resolved(from:)`-Muster wie
  `ArticleDateDisplayMode`). Klick auf eine Dropdown-Zeile: `.inFeedivo` öffnet
  ein `ArticleWindowRequest`-Popout-Fenster (bestehende Infrastruktur),
  `.inBrowser` nutzt dieselbe Logik wie die bestehende
  `onOpenOriginal`-Aktion in `ArticleRowView`.

## 4. Settings-UI

Neuer Settings-Tab „Menubar" (Icon `menubar.rectangle`) in `SettingsView.swift`,
strukturell analog zum in Feature 19.1 eingeführten „Artikelliste"-Tab (eigene
`NewSettingsSection`-Case, eigene `NewMenubarSettingsView`-Struct mit
`NewSettingsBlock`). Enthält: Menubar-Icon aktivieren (Toggle), Artikelanzahl
(Stepper 3–10), Klick-Verhalten (Picker `.inFeedivo`/`.inBrowser`), Dock-Icon
ausblenden (Toggle).

## Testing

- Unit-Tests: `ArticleStatusStore.markAllUnreadAsRead()` (setzt wirklich alle
  ungelesenen Artikel auf gelesen, nicht nur eine Teilmenge), die neue
  `newestUnread(limit:)`-Query (Sortierung, Limit, nur ungelesene Artikel,
  feed-übergreifend), `MenubarArticleClickBehavior.resolved(from:)` und
  `MenubarSettings`-Defaults.
- Kein automatisierter UI-Test für `MenuBarExtra` selbst — macOS bietet dafür
  keine sinnvolle Testbarkeit, und in dieser Umgebung ist kein computer-use
  für native macOS-Apps verfügbar. Manuelle Verifikation nötig (siehe unten).

## Manuelle Verifikation (nicht automatisierbar)

- Menubar-Icon erscheint/verschwindet korrekt beim Toggle
- Badge-Zähler stimmt mit Dock-Badge überein und aktualisiert sich live
- Dropdown zeigt korrekte Artikelanzahl gemäß Einstellung, Refresh-Spinner
  läuft sichtbar während des Refreshs
- „Alle als gelesen markieren" leert das Dropdown und aktualisiert
  Sidebar-Badges sofort
- Dock-Icon-Toggle wirkt ohne Neustart, Hauptfenster/Shortcuts bleiben nutzbar
- Artikel-Klick öffnet je nach Einstellung im Feedivo-Fenster oder Browser

## Out of Scope

- Kein eigenständiger „Menubar-only"-Modus ohne Hauptfenster (siehe
  Klärungsfrage: Hauptfenster bleibt immer erreichbar)
- Keine Änderung an der bestehenden feed-/listen-scoped
  `markRowsRead(.allVisible)`-Aktion in der regulären Artikelliste — die neue
  `markAllUnreadAsRead()` ist eine zusätzliche, unabhängige Methode
- Kein `NSStatusItem`/`NSPopover`-Fallback für ältere macOS-Versionen
  (Mindest-macOS ist bereits 14.0, `MenuBarExtra` seit 13.0 verfügbar)
