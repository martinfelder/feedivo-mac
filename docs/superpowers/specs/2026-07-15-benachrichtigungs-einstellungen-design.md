# Design: Benachrichtigungs-Einstellungen überarbeiten

**Datum:** 2026-07-15
**Status:** Zur Review

## Kontext

Feedivo hat bereits eine funktionierende Benachrichtigungs-Pipeline: pro-Feed-Toggle
(`FeedRecord.isNotificationEnabled`, konfiguriert in `FeedPropertiesView`) und
regelbasierte Benachrichtigungen mit Priorität (`RuleRecord.notificationPriority`,
konfiguriert im `RuleWizardView` als `.notify`-Aktion). Beide laufen über die
gemeinsame Zustell-Pipeline `FeedNotificationService.present(...)`.

Die Einstellungsseite (`NotificationSettingsView` in `SettingsView.swift`) bildet davon
aber kaum etwas ab: sie zeigt nur den macOS-Berechtigungsstatus (mit Anfrage-Button bei
`notDetermined`) plus zwei reine Info-Zeilen, die auf Feed-Eigenschaften bzw. RuleWizard
verweisen — keine echten Einstellungen, keine Hilfe bei blockierter Erlaubnis, keine
app-weiten Optionen.

## Ziele

1. Bei blockierter macOS-Erlaubnis (`denied`) einen direkten Weg zu den
   Systemeinstellungen anbieten statt nur Text.
2. Einen globalen Master-Schalter ergänzen, der alle Benachrichtigungen (Feed + Regeln)
   app-weit übersteuert, unabhängig von einzelnen Feed-/Regel-Einstellungen.
3. Ein einstellbares Standardverhalten für neu hinzugefügte Feeds ergänzen (aktuell fest
   auf "aus" verdrahtet).
4. Eine Test-Benachrichtigung anbieten, um Zustellung/Sound sofort zu prüfen, ohne auf
   einen echten Feed-Refresh oder Regel-Treffer zu warten.
5. Nebenbei: veralteten Hinweistext bei den Regel-Benachrichtigungen korrigieren (verweist
   noch auf eine als "kommt noch" beschriebene Funktion, die längst existiert).

## Nicht-Ziele

- Keine Änderung an der pro-Feed- oder pro-Regel-Konfiguration selbst (bleibt in
  `FeedPropertiesView` bzw. `RuleWizardView`).
- Kein Klick-zu-Artikel-Navigation für Benachrichtigungen (fehlender
  `UNUserNotificationCenterDelegate` — eigenes, größeres Thema, hier bewusst
  ausgeklammert).
- Keine neuen Sound-/Darstellungsoptionen jenseits der Test-Benachrichtigung.

## Datenmodell

Neue `Feedivo/Services/NotificationSettings.swift`, nach dem bestehenden Muster von
`AppIconBadgeSettings.swift`/`CloudSyncSettings.swift`:

```swift
import Foundation

enum NotificationSettings {
    static let isMasterEnabledKey = "notifications.master.isEnabled"
    static let defaultIsMasterEnabled = true

    static let defaultEnabledForNewFeedsKey = "notifications.newFeeds.defaultEnabled"
    static let defaultEnabledForNewFeedsDefault = false

    /// Liest den Master-Schalter sicher aus `UserDefaults`. Ein naives
    /// `UserDefaults.bool(forKey:)` liefert bei fehlendem Key `false` statt des
    /// gewünschten Defaults `true` — Bestandsnutzer, die diese Einstellungsseite nie
    /// öffnen, würden sonst beim Update sämtliche Benachrichtigungen verlieren. Muster
    /// analog zu `CloudSyncSettings.isEnabled(in:)`.
    static func isMasterEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isMasterEnabledKey) != nil else {
            return defaultIsMasterEnabled
        }
        return defaults.bool(forKey: isMasterEnabledKey)
    }

    /// Gleiche Absicherung wie oben, für den "Standard für neue Feeds"-Schalter.
    static func isEnabledForNewFeeds(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: defaultEnabledForNewFeedsKey) != nil else {
            return defaultEnabledForNewFeedsDefault
        }
        return defaults.bool(forKey: defaultEnabledForNewFeedsKey)
    }
}
```

Beide Defaults sind bewusst so gewählt, dass sich am Verhalten für Bestandsnutzer nichts
ändert: Master-Schalter default `true` (bestehende Feed-/Regel-Einstellungen wirken
unverändert weiter), "Standard für neue Feeds" default `false` (entspricht 1:1 dem
bisherigen hart verdrahteten `FeedRecord.isNotificationEnabled = false`).

## UI-Struktur

Bleibt innerhalb des bestehenden einzelnen `SettingsBlock(eyebrow:
L10n.settingsNotificationsSection)` — kein neuer Block, analog zum bestehenden Muster
(z. B. Status-Unterabschnitte im "Alte Artikel"-Tab, die auch nur zusätzliche Zeilen im
selben Block sind). Neue Zeilenreihenfolge:

1. **macOS-Erlaubnis** (bestehend, Verhalten je Status erweitert):
   - `notDetermined` → "Erlaubnis anfragen"-Button (unverändert)
   - `denied` → **neu:** "Systemeinstellungen öffnen"-Button statt reinem Text
   - `authorized`/`provisional`/`ephemeral` → Status-Text (unverändert)
2. **Neu:** Master-Schalter — Toggle "Benachrichtigungen aktiviert", Beschreibung erklärt
   die übersteuernde Wirkung auf Feed- und Regel-Benachrichtigungen.
3. **Neu:** Standard für neue Feeds — Toggle "Neue Feeds automatisch benachrichtigen",
   mit Hinweis, dass bestehende Feeds weiterhin einzeln in ihren Eigenschaften
   umstellbar bleiben.
4. **Neu:** Test-Benachrichtigung — Button "Test senden".
5. Bestehende Info-Zeile "Feed-Benachrichtigungen" (Verweis auf Feed-Eigenschaften) —
   Wording leicht geschärft, damit sie sich nicht mit Punkt 3 überschneidet.
6. Bestehende Info-Zeile "Regel-Benachrichtigungen" — Text korrigiert (siehe unten).

## Verhalten im Detail

### Master-Schalter-Integration

`FeedNotificationService.present(...)` (private, gemeinsame Zustell-Pipeline für
Feed-Refresh- und Regel-Benachrichtigungen) bekommt einen neuen Parameter
`respectsMasterSwitch: Bool = true`:

```swift
private static func present(
    title: String,
    body: String,
    userInfo: [String: Any],
    identifierPrefix: String,
    isCritical: Bool,
    respectsMasterSwitch: Bool = true
) async {
    if respectsMasterSwitch, !NotificationSettings.isMasterEnabled() {
        return
    }

    guard await isAuthorized() else {
        return
    }
    // ... unverändert
}
```

Der Check steht bewusst vor `isAuthorized()`, damit bei ausgeschaltetem Master-Schalter
auch keine unnötige Berechtigungsanfrage bei `notDetermined` ausgelöst wird.

`presentRefreshSummary(for:)` und `presentRuleSummary(for:)` rufen `present(...)`
unverändert ohne den neuen Parameter auf (Default `true` greift).

### Test-Benachrichtigung

Neue öffentliche Funktion in `FeedNotificationService`:

```swift
static func presentTest() async {
    await present(
        title: L10n.notificationTestTitle,
        body: L10n.notificationTestBody,
        userInfo: ["feedivoNotificationType": "test"],
        identifierPrefix: "test",
        isCritical: false,
        respectsMasterSwitch: false
    )
}
```

Bewusst `respectsMasterSwitch: false` — ein expliziter Klick auf "Test senden" ist
eindeutig gewollt, auch wenn der Nutzer automatische Benachrichtigungen gerade pausiert
hat. Respektiert weiterhin die macOS-Berechtigung über `isAuthorized()` (fragt bei
`notDetermined` automatisch nach, liefert bei `denied` still nichts — wie der Rest der
Pipeline).

### Standard für neue Feeds

Zwei Stellen in `SQLiteFeedSubscriptionService.swift` bauen aktuell unabhängig
voneinander `FeedRecord(...)` ohne explizites `isNotificationEnabled` (nutzen damit den
hart verdrahteten Default `false` aus `FeedRecord.init`):

- `addFeed(...)` (~Zeile 121)
- `importOPMLFeeds(...)` (~Zeile 242, OPML-Import)

Beide bekommen `isNotificationEnabled: NotificationSettings.isEnabledForNewFeeds()`
explizit gesetzt.

### "Systemeinstellungen öffnen"-Button

Bei `denied` ersetzt ein Button den reinen Status-Text:

```swift
Button(L10n.settingsNotificationsPermissionOpenSystemSettings) {
    NotificationSettings.openSystemNotificationSettings()
}
```

```swift
// in NotificationSettings.swift
static let appSpecificSystemSettingsURLString =
    "x-apple.systempreferences:com.apple.Notifications-Settings.extension?ch.martin.Feedivo"
static let fallbackSystemSettingsURLString =
    "x-apple.systempreferences:com.apple.preference.notifications"

static func openSystemNotificationSettings() {
    guard let url = URL(string: appSpecificSystemSettingsURLString) else {
        return
    }
    NSWorkspace.shared.open(url)
}
```

Die App-spezifische URL ist ein undokumentiertes, aber seit macOS Ventura verlässlich
genutztes Deep-Link-Schema. **Wichtig:** `NSWorkspace.open(_:)` liefert zur Laufzeit kein
verlässliches Signal darüber, ob die URL tatsächlich auf der App-eigenen Seite gelandet
ist statt nur auf der allgemeinen Übersicht — ein automatischer Laufzeit-Fallback wäre
damit nicht robust genug, um sich darauf zu verlassen. Stattdessen: Beim Live-Test in
Task-Review/Verifikation prüfen, ob `appSpecificSystemSettingsURLString` tatsächlich zur
Feedivo-eigenen Seite springt. Tut sie das nicht zuverlässig, wird stattdessen fest auf
`fallbackSystemSettingsURLString` (allgemeine Benachrichtigungs-Übersicht) umgestellt —
als bewusste Code-Entscheidung nach dem Test, nicht als automatische Laufzeit-Logik.

### Stale-Text-Fix

`settings.notifications.rules.description` sagt aktuell "Regelbasierte
Benachrichtigungen werden danach als eigene Regel-Aktion im RuleWizard ergänzt" — die
Regel-Aktion existiert aber bereits (`RuleWizardView`, `.notify`-Fall). Wird korrigiert
zu einer Formulierung analog zur Feed-Zeile: "Regelbasierte Benachrichtigungen werden pro
Regel im Regel-Assistenten konfiguriert."

## Neue L10n-Keys

- `settings.notifications.permission.openSystemSettings` ("Systemeinstellungen öffnen")
- `settings.notifications.master.title` / `.description`
- `settings.notifications.newFeedsDefault.title` / `.description`
- `settings.notifications.test.title` / `.description` / `.button`
- `notification.test.title` / `.body` (Inhalt der Test-Benachrichtigung selbst)

Bestehender Key `settings.notifications.rules.description` wird inhaltlich korrigiert,
nicht umbenannt (kein neuer Key nötig).

**Wichtig (bekannter Gotcha, siehe CLAUDE.md):** Neue `L10n.swift`-Konstanten, die nur
indirekt referenziert werden, erzeugen beim Build keinen automatischen Stub-Eintrag in
`Localizable.xcstrings`. Jeder neue Key muss nach der Implementierung per
`grep -c "<key>" Feedivo/Resources/Localizable.xcstrings` geprüft und ggf. manuell
(gezielte `Edit`, kein `json.dump`-Rewrite — siehe Gotcha zur Reformatierung) ergänzt
werden.

## Tests

- `NotificationSettingsTests`: `isMasterEnabled(in:)` und `isEnabledForNewFeeds(in:)`
  jeweils mit leerem `UserDefaults` (muss Default liefern, nicht `false`) und mit
  explizit gesetztem Wert.
- `FeedNotificationServiceTests`: `present(...)` liefert bei `isMasterEnabled == false`
  und `respectsMasterSwitch == true` keine Zustellung; bei `respectsMasterSwitch == false`
  weiterhin.
- `SQLiteFeedSubscriptionServiceTests`: `addFeed(...)` und `importOPMLFeeds(...)`
  respektieren `NotificationSettings.isEnabledForNewFeeds()` (beide Werte: `true`/`false`).

## Risiken / offene Punkte

- Die App-spezifische Systemeinstellungen-URL ist undokumentiert und nicht durch Apple
  garantiert stabil — muss live verifiziert werden, Fallback ist eingeplant.
- Klick-zu-Artikel-Navigation bei Benachrichtigungen bleibt bewusst außen vor (separates,
  größeres Thema).
