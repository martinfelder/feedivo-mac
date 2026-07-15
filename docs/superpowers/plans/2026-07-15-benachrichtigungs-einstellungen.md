# Benachrichtigungs-Einstellungen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die Benachrichtigungs-Einstellungsseite (`NotificationSettingsView` in `SettingsView.swift`) von reinen Info-Texten zu echten App-weiten Einstellungen ausbauen: Master-Schalter, Standard-Verhalten für neue Feeds, Test-Benachrichtigung, direkter Sprung zu den Systemeinstellungen bei blockierter Erlaubnis.

**Architecture:** Neues `NotificationSettings.swift` (AppStorage-Key-Enum nach dem Muster von `CloudSyncSettings.swift`) als Datenmodell. `FeedNotificationService.present(...)` bekommt einen Master-Schalter-Gate direkt in der bestehenden gemeinsamen Zustell-Pipeline. `SQLiteFeedSubscriptionService` liest den Default für neue Feeds über einen injizierbaren `UserDefaults` statt des bisherigen hart verdrahteten `FeedRecord`-Defaults. Die UI bleibt im bestehenden `SettingsBlock`-Layout von `SettingsView.swift`.

**Tech Stack:** SwiftUI, `@AppStorage`/`UserDefaults`, `UserNotifications` (`UNUserNotificationCenter`), `AppKit` (`NSWorkspace` für den Systemeinstellungen-Deep-Link), GRDB (nur indirekt betroffen), Swift Testing (`import Testing`, kein XCTest).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- Kein SwiftData — GRDB/SQLite ist die alleinige Persistenz; `FeedRecord`/`FeedStore` bleiben unverändert bis auf den bereits bestehenden `isNotificationEnabled`-Parameter.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`), kein XCTest. Suite-Struct ohne `@Suite`-Attribut, außer wenn Serialisierung nötig ist (hier nicht der Fall).
- Naiver `UserDefaults.bool(forKey:)`/`.integer(forKey:)`-Zugriff ohne `object(forKey:) != nil`-Vorabprüfung ist verboten für neue AppStorage-Keys mit einem Default ungleich dem Schwellenwert-Default des Typs (hier: `isMasterEnabled` default `true` — siehe CLAUDE.md-Gotcha zu `retentionDays`).
- Neue `L10n.swift`-Konstanten, die nur indirekt referenziert werden (nicht als Literal in `Text(...)`), erzeugen **keinen** automatischen Stub in `Localizable.xcstrings` — jeder neue Key muss manuell per gezieltem `Edit` ergänzt werden (kein `json.dump`-Rewrite der ganzen Datei — das reformatiert alle ~38.000 Zeilen und macht den Diff unlesbar).
- Alle neuen benutzersichtbaren Strings brauchen alle vier Sprachen: `de`, `en`, `fr`, `it`.
- Build-Verifikation ausschließlich über `xcodebuild build` — SourceKit-Diagnosen in der IDE sind für dieses Projekt bekanntermaßen unzuverlässig (CLAUDE.md-Gotcha).
- `NSWorkspace.shared.open(_:)` in Tests **nicht** aufrufen — das öffnet echte Systemeinstellungen während des Testlaufs. `openSystemNotificationSettings()` bleibt ungetestet und wird stattdessen manuell live verifiziert.

---

### Task 1: NotificationSettings.swift — Datenmodell

**Files:**
- Create: `Feedivo/Services/NotificationSettings.swift`
- Test: `FeedivoTests/NotificationSettingsTests.swift`

**Interfaces:**
- Produces: `NotificationSettings.isMasterEnabledKey: String`, `NotificationSettings.defaultIsMasterEnabled: Bool`, `NotificationSettings.defaultEnabledForNewFeedsKey: String`, `NotificationSettings.defaultEnabledForNewFeedsDefault: Bool`, `NotificationSettings.appSpecificSystemSettingsURLString: String`, `NotificationSettings.fallbackSystemSettingsURLString: String`, `static func NotificationSettings.isMasterEnabled(in defaults: UserDefaults = .standard) -> Bool`, `static func NotificationSettings.isEnabledForNewFeeds(in defaults: UserDefaults = .standard) -> Bool`, `static func NotificationSettings.openSystemNotificationSettings()`.

- [ ] **Step 1: Write the failing tests**

Create `FeedivoTests/NotificationSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import Feedivo

struct NotificationSettingsTests {
    @Test func defaultsSindWieDokumentiert() {
        #expect(NotificationSettings.isMasterEnabledKey == "notifications.master.isEnabled")
        #expect(NotificationSettings.defaultIsMasterEnabled == true)
        #expect(NotificationSettings.defaultEnabledForNewFeedsKey == "notifications.newFeeds.defaultEnabled")
        #expect(NotificationSettings.defaultEnabledForNewFeedsDefault == false)
    }

    @Test func isMasterEnabledLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()

        #expect(NotificationSettings.isMasterEnabled(in: defaults) == true)
    }

    @Test func isMasterEnabledLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: NotificationSettings.isMasterEnabledKey)

        #expect(NotificationSettings.isMasterEnabled(in: defaults) == false)

        defaults.set(true, forKey: NotificationSettings.isMasterEnabledKey)

        #expect(NotificationSettings.isMasterEnabled(in: defaults) == true)
    }

    @Test func isEnabledForNewFeedsLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()

        #expect(NotificationSettings.isEnabledForNewFeeds(in: defaults) == false)
    }

    @Test func isEnabledForNewFeedsLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: NotificationSettings.defaultEnabledForNewFeedsKey)

        #expect(NotificationSettings.isEnabledForNewFeeds(in: defaults) == true)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.NotificationSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NotificationSettingsTests`
Expected: FAIL — `NotificationSettings` existiert noch nicht (Compile-Fehler "cannot find 'NotificationSettings' in scope").

- [ ] **Step 3: Write minimal implementation**

Create `Feedivo/Services/NotificationSettings.swift`:

```swift
import Foundation
import AppKit

enum NotificationSettings {
    static let isMasterEnabledKey = "notifications.master.isEnabled"
    static let defaultIsMasterEnabled = true

    static let defaultEnabledForNewFeedsKey = "notifications.newFeeds.defaultEnabled"
    static let defaultEnabledForNewFeedsDefault = false

    static let appSpecificSystemSettingsURLString =
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension?ch.martin.Feedivo"
    static let fallbackSystemSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.notifications"

    /// Liest den Master-Schalter sicher aus `UserDefaults`. Ein naives
    /// `UserDefaults.bool(forKey:)` liefert bei fehlendem Key `false` statt des
    /// gewünschten Defaults `true` — Bestandsnutzer, die diese Einstellungsseite nie
    /// öffnen, würden sonst beim Update sämtliche Benachrichtigungen verlieren.
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

    /// Springt zur App-eigenen Benachrichtigungsseite in den Systemeinstellungen.
    /// Bewusst ohne Laufzeit-Fallback auf `fallbackSystemSettingsURLString`:
    /// `NSWorkspace.open(_:)` liefert kein verlässliches Signal, ob die private
    /// URL tatsächlich auf der App-eigenen Seite statt nur der allgemeinen
    /// Übersicht gelandet ist. Welche der beiden Konstanten hier verwendet wird,
    /// ist stattdessen eine Code-Entscheidung nach manueller Live-Verifikation.
    static func openSystemNotificationSettings() {
        guard let url = URL(string: appSpecificSystemSettingsURLString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NotificationSettingsTests`
Expected: PASS — alle 5 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/NotificationSettings.swift FeedivoTests/NotificationSettingsTests.swift
git commit -m "Feature: NotificationSettings-Datenmodell (Master-Schalter, Neue-Feeds-Default, Systemeinstellungen-Link)"
```

---

### Task 2: L10n-Keys + Localizable.xcstrings

**Files:**
- Modify: `Feedivo/Resources/L10n.swift:390` (Einfügepunkt nach `settingsNotificationsRulesDescription`)
- Modify: `Feedivo/Resources/L10n.swift:641` (Einfügepunkt nach `ruleNotificationFallbackRuleName`)
- Modify: `Feedivo/Resources/Localizable.xcstrings` (3 neue Einfügungen + 2 Wert-Korrekturen)

**Interfaces:**
- Consumes: nichts aus Task 1.
- Produces: `L10n.settingsNotificationsPermissionOpenSystemSettings`, `L10n.settingsNotificationsMasterTitle`, `L10n.settingsNotificationsMasterDescription`, `L10n.settingsNotificationsNewFeedsDefaultTitle`, `L10n.settingsNotificationsNewFeedsDefaultDescription`, `L10n.settingsNotificationsTestTitle`, `L10n.settingsNotificationsTestDescription`, `L10n.settingsNotificationsTestButton` (alle `LocalizedStringKey`), sowie `L10n.notificationTestTitle`, `L10n.notificationTestBody` (beide `String`).

- [ ] **Step 1: Neue `LocalizedStringKey`-Konstanten in L10n.swift ergänzen**

In `Feedivo/Resources/L10n.swift`, Zeile 390 (`static let settingsNotificationsRulesDescription = LocalizedStringKey("settings.notifications.rules.description")`) — direkt danach einfügen:

```swift
    static let settingsNotificationsPermissionOpenSystemSettings = LocalizedStringKey("settings.notifications.permission.openSystemSettings")
    static let settingsNotificationsMasterTitle = LocalizedStringKey("settings.notifications.master.title")
    static let settingsNotificationsMasterDescription = LocalizedStringKey("settings.notifications.master.description")
    static let settingsNotificationsNewFeedsDefaultTitle = LocalizedStringKey("settings.notifications.newFeedsDefault.title")
    static let settingsNotificationsNewFeedsDefaultDescription = LocalizedStringKey("settings.notifications.newFeedsDefault.description")
    static let settingsNotificationsTestTitle = LocalizedStringKey("settings.notifications.test.title")
    static let settingsNotificationsTestDescription = LocalizedStringKey("settings.notifications.test.description")
    static let settingsNotificationsTestButton = LocalizedStringKey("settings.notifications.test.button")
```

- [ ] **Step 2: Neue `String`-Konstanten für den Notification-Inhalt ergänzen**

In `Feedivo/Resources/L10n.swift`, Zeile 641 (`static let ruleNotificationFallbackRuleName = String(localized: "notification.rule.fallbackRuleName")`) — direkt danach einfügen:

```swift
    static let notificationTestTitle = String(localized: "notification.test.title")
    static let notificationTestBody = String(localized: "notification.test.body")
```

- [ ] **Step 3: Neue Einträge in Localizable.xcstrings einfügen (Block 1: master/newFeedsDefault)**

In `Feedivo/Resources/Localizable.xcstrings` den bestehenden Eintrag `"settings.notifications.feed.title"` (endet mit `    },` direkt vor `"settings.notifications.permission.allowed"`) per `Edit` erweitern — `old_string` ist der exakte Übergang zwischen beiden bestehenden Einträgen, `new_string` fügt die vier neuen Blöcke dazwischen ein:

```
old_string:
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifiche dei feed"
          }
        }
      }
    },
    "settings.notifications.permission.allowed" : {

new_string:
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifiche dei feed"
          }
        }
      }
    },
    "settings.notifications.master.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Schaltet alle Feed- und Regel-Benachrichtigungen app-weit aus, unabhängig von einzelnen Feed- oder Regel-Einstellungen."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Turns off all feed and rule notifications app-wide, regardless of individual feed or rule settings."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Désactive toutes les notifications de flux et de règles dans toute l'application, indépendamment des réglages individuels."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Disattiva tutte le notifiche di feed e regole nell'intera app, indipendentemente dalle impostazioni individuali."
          }
        }
      }
    },
    "settings.notifications.master.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Benachrichtigungen aktiviert"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifications Enabled"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifications activées"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifiche attivate"
          }
        }
      }
    },
    "settings.notifications.newFeedsDefault.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Legt fest, ob neu hinzugefügte Feeds Benachrichtigungen standardmäßig aktiviert bekommen. Bestehende Feeds bleiben davon unberührt und lassen sich weiterhin einzeln in den Feed-Eigenschaften umstellen."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Controls whether newly added feeds have notifications enabled by default. Existing feeds are unaffected and remain individually configurable in Feed Properties."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Détermine si les flux nouvellement ajoutés ont les notifications activées par défaut. Les flux existants ne sont pas concernés et restent configurables individuellement dans leurs propriétés."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Determina se i feed appena aggiunti hanno le notifiche attivate per impostazione predefinita. I feed esistenti non sono interessati e restano configurabili singolarmente nelle proprietà del feed."
          }
        }
      }
    },
    "settings.notifications.newFeedsDefault.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Neue Feeds automatisch benachrichtigen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notify New Feeds Automatically"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifier automatiquement les nouveaux flux"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifica automaticamente i nuovi feed"
          }
        }
      }
    },
    "settings.notifications.permission.allowed" : {
```

- [ ] **Step 4: Neuer Eintrag in Localizable.xcstrings (Block 2: permission.openSystemSettings)**

Zwischen den bestehenden Einträgen `"settings.notifications.permission.notDetermined"` und `"settings.notifications.permission.request"` per `Edit` einfügen:

```
old_string:
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feedivo non ha ancora chiesto l’autorizzazione a macOS."
          }
        }
      }
    },
    "settings.notifications.permission.request" : {

new_string:
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feedivo non ha ancora chiesto l’autorizzazione a macOS."
          }
        }
      }
    },
    "settings.notifications.permission.openSystemSettings" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Systemeinstellungen öffnen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open System Settings"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ouvrir les réglages système"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apri Impostazioni di Sistema"
          }
        }
      }
    },
    "settings.notifications.permission.request" : {
```

**Hinweis für den alten `it`-Wert:** Der Apostroph in `"Feedivo non ha ancora chiesto l’autorizzazione a macOS."` ist ein typografischer Apostroph (`’`, U+2019), kein gerades ASCII-Apostroph — beim Anlegen von `old_string`/`new_string` exakt so übernehmen, sonst matcht `Edit` nicht.

- [ ] **Step 5: Neue Einträge in Localizable.xcstrings (Block 3: test.button/description/title)**

Zwischen den bestehenden Einträgen `"settings.notifications.section"` und `"settings.offline.automation.description"` per `Edit` einfügen:

```
old_string:
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifiche"
          }
        }
      }
    },
    "settings.offline.automation.description" : {

new_string:
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifiche"
          }
        }
      }
    },
    "settings.notifications.test.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Test senden"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Send Test"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Envoyer le test"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Invia prova"
          }
        }
      }
    },
    "settings.notifications.test.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sendet sofort eine Beispiel-Benachrichtigung, um Zustellung und Sound zu prüfen."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sends a sample notification immediately to check delivery and sound."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Envoie immédiatement une notification d'exemple pour vérifier la remise et le son."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Invia immediatamente una notifica di esempio per verificare la consegna e il suono."
          }
        }
      }
    },
    "settings.notifications.test.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Test-Benachrichtigung"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Test Notification"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notification de test"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifica di prova"
          }
        }
      }
    },
    "settings.offline.automation.description" : {
```

- [ ] **Step 6: Neuer Eintrag in Localizable.xcstrings (Block 4: notification.test.title/body)**

Zwischen den bestehenden Einträgen `"notification.rule.summary.title"` und `"Oberfläche"` per `Edit` einfügen. Anker-Text (Ende des `it`-Blocks von `notification.rule.summary.title`, ein Plural-Eintrag):

```
old_string:
        "it" : {
          "variations" : {
            "plural" : {
              "many" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld nuovi articoli %@"
                }
              },
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld nuovi articoli %@"
                }
              }
            }
          }
        }
      }
    },
    "Oberfläche" : {

new_string:
        "it" : {
          "variations" : {
            "plural" : {
              "many" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld nuovi articoli %@"
                }
              },
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld nuovi articoli %@"
                }
              }
            }
          }
        }
      }
    },
    "notification.test.body" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Wenn du das hier siehst, funktionieren Benachrichtigungen einwandfrei."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "If you see this, notifications are working correctly."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Si vous voyez ceci, les notifications fonctionnent correctement."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Se vedi questo messaggio, le notifiche funzionano correttamente."
          }
        }
      }
    },
    "notification.test.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feedivo Test-Benachrichtigung"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feedivo Test Notification"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notification de test Feedivo"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notifica di prova Feedivo"
          }
        }
      }
    },
    "Oberfläche" : {
```

(`notification.test.body` kommt alphabetisch vor `notification.test.title` — `b` < `t`.)

- [ ] **Step 7: Bestehenden Eintrag `settings.notifications.feed.description` korrigieren**

```
old_string:
    "settings.notifications.feed.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed-Benachrichtigungen werden pro Feed in den Feed-Eigenschaften aktiviert."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed notifications are enabled per feed in Feed Properties."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Les notifications de flux sont activées par flux dans les propriétés du flux."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Le notifiche dei feed si attivano per singolo feed nelle proprietà del feed."
          }
        }
      }
    },

new_string:
    "settings.notifications.feed.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed-Benachrichtigungen werden pro Feed in den Feed-Eigenschaften aktiviert; der Standard für neu hinzugefügte Feeds lässt sich oben einstellen."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Feed notifications are enabled per feed in Feed Properties; the default for newly added feeds can be set above."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Les notifications de flux sont activées par flux dans les propriétés du flux ; le réglage par défaut pour les nouveaux flux se trouve ci-dessus."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Le notifiche dei feed si attivano per singolo feed nelle proprietà del feed; il valore predefinito per i nuovi feed si imposta qui sopra."
          }
        }
      }
    },

```

- [ ] **Step 8: Bestehenden Eintrag `settings.notifications.rules.description` korrigieren (stale-Text-Fix)**

```
old_string:
    "settings.notifications.rules.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Regelbasierte Benachrichtigungen werden danach als eigene Regel-Aktion im RuleWizard ergänzt."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rule-based notifications will then be added as a dedicated rule action in the Rule Wizard."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Les notifications basées sur des règles seront ensuite ajoutées comme action dédiée dans l’assistant de règles."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Le notifiche basate su regole saranno poi aggiunte come azione dedicata nel wizard delle regole."
          }
        }
      }
    },

new_string:
    "settings.notifications.rules.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Regelbasierte Benachrichtigungen werden pro Regel im Regel-Assistenten konfiguriert."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rule-based notifications are configured per rule in the Rule Wizard."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Les notifications basées sur des règles se configurent par règle dans l'assistant de règles."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Le notifiche basate su regole si configurano per regola nella procedura guidata delle regole."
          }
        }
      }
    },

```

- [ ] **Step 9: Verifizieren, dass alle neuen Keys im Katalog vorhanden sind**

Run:
```bash
for key in \
  "settings.notifications.permission.openSystemSettings" \
  "settings.notifications.master.title" \
  "settings.notifications.master.description" \
  "settings.notifications.newFeedsDefault.title" \
  "settings.notifications.newFeedsDefault.description" \
  "settings.notifications.test.title" \
  "settings.notifications.test.description" \
  "settings.notifications.test.button" \
  "notification.test.title" \
  "notification.test.body"; do
  count=$(grep -c "\"$key\"" Feedivo/Resources/Localizable.xcstrings)
  echo "$key: $count"
done
```
Expected: Jede Zeile zeigt `1` (jeder Key genau einmal vorhanden).

- [ ] **Step 10: Build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 11: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: L10n-Keys für Benachrichtigungs-Einstellungen (Master-Schalter, Neue-Feeds-Default, Test, Systemeinstellungen) + Stale-Text-Fix Regel-Benachrichtigungen"
```

---

### Task 3: FeedNotificationService — Master-Schalter + Test-Benachrichtigung

**Files:**
- Modify: `Feedivo/Services/FeedNotificationService.swift`

**Interfaces:**
- Consumes: `NotificationSettings.isMasterEnabled(in:)` (Task 1), `L10n.notificationTestTitle`, `L10n.notificationTestBody` (Task 2).
- Produces: `static func FeedNotificationService.presentTest() async`. Ändert Signatur von `private static func present(...)` um den neuen Parameter `respectsMasterSwitch: Bool = true` (rein additiv, bestehende Aufrufer unverändert lauffähig).

- [ ] **Step 1: `present(...)` um Master-Schalter-Gate erweitern**

In `Feedivo/Services/FeedNotificationService.swift`, die bestehende `present`-Methode ersetzen:

```
old_string:
    private static func present(
        title: String,
        body: String,
        userInfo: [String: Any],
        identifierPrefix: String,
        isCritical: Bool
    ) async {
        guard await isAuthorized() else {
            return
        }

new_string:
    private static func present(
        title: String,
        body: String,
        userInfo: [String: Any],
        identifierPrefix: String,
        isCritical: Bool,
        respectsMasterSwitch: Bool = true
    ) async {
        // Steht bewusst vor isAuthorized(): bei ausgeschaltetem Master-Schalter soll
        // auch keine unnötige Berechtigungsanfrage bei notDetermined ausgelöst werden.
        if respectsMasterSwitch, !NotificationSettings.isMasterEnabled() {
            return
        }

        guard await isAuthorized() else {
            return
        }
```

- [ ] **Step 2: `presentTest()` ergänzen**

Direkt nach dem Ende von `presentRuleSummary(for:)` (nach dessen schließender `}`, vor dem Doc-Kommentar zu `present`) einfügen:

```
old_string:
        await present(
            title: summary.title,
            body: summary.body,
            userInfo: [
                "feedivoNotificationType": "rule",
                "ruleIDs": summary.ruleIDs.map(\.uuidString)
            ],
            identifierPrefix: "rule",
            isCritical: summary.priority == .critical
        )
    }

    /// Gemeinsame Delivery-Pipeline für Feed-Refresh- und Regel-Notifications.

new_string:
        await present(
            title: summary.title,
            body: summary.body,
            userInfo: [
                "feedivoNotificationType": "rule",
                "ruleIDs": summary.ruleIDs.map(\.uuidString)
            ],
            identifierPrefix: "rule",
            isCritical: summary.priority == .critical
        )
    }

    /// Test-Benachrichtigung für die Einstellungsseite — bewusst
    /// `respectsMasterSwitch: false`, da ein expliziter Klick auf "Test senden"
    /// eindeutig gewollt ist, auch wenn der Nutzer automatische Benachrichtigungen
    /// gerade pausiert hat. Respektiert weiterhin die macOS-Berechtigung.
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

    /// Gemeinsame Delivery-Pipeline für Feed-Refresh- und Regel-Notifications.
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

Kein neuer Unit-Test für `present`/`presentTest`: Beide sprechen den echten `UNUserNotificationCenter` an — schon die bestehenden Tests in `FeedNotificationServiceTests.swift` decken ausschließlich die reinen Funktionen `summary(from:)`/`ruleSummary(from:)` ab, nicht die Zustellung selbst. Diese Grenze bleibt hier bewusst bestehen (kein Mock-Seam für `UNUserNotificationCenter` im Projekt vorhanden).

- [ ] **Step 4: Run existing tests to confirm no regression**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedNotificationServiceTests -only-testing:FeedivoTests/RuleNotificationServiceTests`
Expected: PASS — beide bestehenden Suiten weiterhin grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/FeedNotificationService.swift
git commit -m "Feature: Master-Schalter-Gate + Test-Benachrichtigung in FeedNotificationService"
```

---

### Task 4: SQLiteFeedSubscriptionService — Standard für neue Feeds

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift` (Init, `addFeed`, `importOPMLFeeds`)
- Test: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`

**Interfaces:**
- Consumes: `NotificationSettings.isEnabledForNewFeeds(in:)` (Task 1).
- Produces: Neuer `userDefaults: UserDefaults = .standard`-Parameter am `SQLiteFeedSubscriptionService.init(...)` (additiv, bestehende Aufrufer — u. a. `FeedViewModel` — bleiben unverändert lauffähig).

- [ ] **Step 1: Write the failing tests**

In `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`, direkt nach `addFeedOhneFolderNameLaesstOrdnerLeer()` einfügen:

```swift
    @MainActor
    @Test func addFeedRespektiertNotificationDefaultFuerNeueFeedsWennAktiviert() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let userDefaults = try temporaryNotificationUserDefaults()
        userDefaults.set(true, forKey: NotificationSettings.defaultEnabledForNewFeedsKey)

        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Benachrichtigter Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil },
            userDefaults: userDefaults
        )

        _ = try await service.addFeed(urlString: "https://example.com/feed.xml")

        let feed = try #require(try FeedStore(database: database).feeds().first)
        #expect(feed.isNotificationEnabled == true)
    }

    @MainActor
    @Test func addFeedRespektiertNotificationDefaultFuerNeueFeedsWennDeaktiviert() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let userDefaults = try temporaryNotificationUserDefaults()
        userDefaults.set(false, forKey: NotificationSettings.defaultEnabledForNewFeedsKey)

        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Unbenachrichtigter Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil },
            userDefaults: userDefaults
        )

        _ = try await service.addFeed(urlString: "https://example.com/feed.xml")

        let feed = try #require(try FeedStore(database: database).feeds().first)
        #expect(feed.isNotificationEnabled == false)
    }
```

Am Ende der Datei (auf oberster Ebene, außerhalb des `struct SQLiteFeedSubscriptionServiceTests`-Blocks, analog zur bestehenden `makeThreadObservingFeedFetcher`-Hilfsfunktion) einfügen:

```swift

private func temporaryNotificationUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.SQLiteFeedSubscriptionService.Notifications.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests`
Expected: FAIL — Compile-Fehler, `SQLiteFeedSubscriptionService.init` kennt noch keinen `userDefaults`-Parameter.

- [ ] **Step 3: `userDefaults` in den Init aufnehmen**

In `Feedivo/Services/SQLiteFeedSubscriptionService.swift`:

```
old_string:
    private let database: FeedivoDatabase
    private let fetchFeed: FeedFetcher
    private let discoverFaviconURL: FaviconFetcher
    private let articleUpsert: ArticleUpserter
    private let afterArticleUpsert: AfterArticleUpsertHook
    private let afterOPMLTagsSave: AfterOPMLTagsSaveHook

    init(
        database: FeedivoDatabase,
        fetchFeed: @escaping FeedFetcher = FeedService.fetchFeed,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        articleUpsert: ArticleUpserter? = nil,
        afterArticleUpsert: @escaping AfterArticleUpsertHook = {},
        afterOPMLTagsSave: @escaping AfterOPMLTagsSaveHook = {}
    ) {
        self.database = database
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
        self.articleUpsert = articleUpsert ?? { inputs in
            try ArticleStore(database: database).upsert(inputs)
        }
        self.afterArticleUpsert = afterArticleUpsert
        self.afterOPMLTagsSave = afterOPMLTagsSave
    }

new_string:
    private let database: FeedivoDatabase
    private let fetchFeed: FeedFetcher
    private let discoverFaviconURL: FaviconFetcher
    private let articleUpsert: ArticleUpserter
    private let afterArticleUpsert: AfterArticleUpsertHook
    private let afterOPMLTagsSave: AfterOPMLTagsSaveHook
    private let userDefaults: UserDefaults

    init(
        database: FeedivoDatabase,
        fetchFeed: @escaping FeedFetcher = FeedService.fetchFeed,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        articleUpsert: ArticleUpserter? = nil,
        afterArticleUpsert: @escaping AfterArticleUpsertHook = {},
        afterOPMLTagsSave: @escaping AfterOPMLTagsSaveHook = {},
        userDefaults: UserDefaults = .standard
    ) {
        self.database = database
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
        self.articleUpsert = articleUpsert ?? { inputs in
            try ArticleStore(database: database).upsert(inputs)
        }
        self.afterArticleUpsert = afterArticleUpsert
        self.afterOPMLTagsSave = afterOPMLTagsSave
        self.userDefaults = userDefaults
    }
```

- [ ] **Step 4: `addFeed(...)` das Notification-Default setzen lassen**

```
old_string:
        let feedRecord = FeedRecord(
            id: feedID,
            url: parsedFeed.sourceURL,
            title: parsedFeed.title,
            originalTitle: parsedFeed.title,
            websiteURL: parsedFeed.siteURL,
            faviconURL: faviconURL,
            folderName: normalizedFolderName,
            refreshIntervalMinutes: BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes),
            createdAt: now,
            updatedAt: now
        )

new_string:
        let feedRecord = FeedRecord(
            id: feedID,
            url: parsedFeed.sourceURL,
            title: parsedFeed.title,
            originalTitle: parsedFeed.title,
            websiteURL: parsedFeed.siteURL,
            faviconURL: faviconURL,
            folderName: normalizedFolderName,
            refreshIntervalMinutes: BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes),
            isNotificationEnabled: NotificationSettings.isEnabledForNewFeeds(in: userDefaults),
            createdAt: now,
            updatedAt: now
        )
```

- [ ] **Step 5: `importOPMLFeeds(...)` das gleiche Default setzen lassen**

```
old_string:
            let feedRecord = FeedRecord(
                id: feedID,
                url: cleanedURL,
                title: title,
                originalTitle: title,
                websiteURL: trimmedNonEmpty(opmlFeed.htmlURL),
                folderName: folderName,
                refreshIntervalMinutes: clampedRefreshInterval,
                createdAt: now,
                updatedAt: now
            )

new_string:
            let feedRecord = FeedRecord(
                id: feedID,
                url: cleanedURL,
                title: title,
                originalTitle: title,
                websiteURL: trimmedNonEmpty(opmlFeed.htmlURL),
                folderName: folderName,
                refreshIntervalMinutes: clampedRefreshInterval,
                isNotificationEnabled: NotificationSettings.isEnabledForNewFeeds(in: userDefaults),
                createdAt: now,
                updatedAt: now
            )
```

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests`
Expected: PASS — alle Tests der Suite grün, einschließlich der zwei neuen.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Services/SQLiteFeedSubscriptionService.swift FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift
git commit -m "Feature: Standard-Benachrichtigungsverhalten für neue Feeds (addFeed + OPML-Import)"
```

---

### Task 5: NotificationSettingsView — UI

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`private struct NotificationSettingsView`)

**Interfaces:**
- Consumes: `NotificationSettings.isMasterEnabledKey`/`.defaultIsMasterEnabled`, `.defaultEnabledForNewFeedsKey`/`.defaultEnabledForNewFeedsDefault`, `.openSystemNotificationSettings()` (Task 1); `FeedNotificationService.presentTest()` (Task 3); alle neuen `L10n.settingsNotifications*`-Keys (Task 2).

- [ ] **Step 1: `NotificationSettingsView` ersetzen**

In `Feedivo/Views/Settings/SettingsView.swift` den kompletten bestehenden `private struct NotificationSettingsView`-Block ersetzen:

```
old_string:
private struct NotificationSettingsView: View {
    @State private var feedNotificationAuthorizationStatus: FeedNotificationAuthorizationStatus = .unknown

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsNotificationsSection) {
                SettingRow(
                    title: L10n.settingsNotificationsPermissionTitle,
                    description: notificationPermissionDescription
                ) {
                    if feedNotificationAuthorizationStatus == .notDetermined {
                        Button(L10n.settingsNotificationsPermissionRequest) {
                            Task {
                                _ = await FeedNotificationService.requestAuthorization()
                                await refreshNotificationAuthorizationStatus()
                            }
                        }
                    } else {
                        Text(permissionStatusText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                InfoRow(
                    iconName: "dot.radiowaves.left.and.right",
                    title: L10n.settingsNotificationsFeedTitle,
                    description: L10n.settingsNotificationsFeedDescription
                )

                InfoRow(
                    iconName: "slider.horizontal.3",
                    title: L10n.settingsNotificationsRulesTitle,
                    description: L10n.settingsNotificationsRulesDescription
                )
            }
        }
        .task {
            await refreshNotificationAuthorizationStatus()
        }
    }

new_string:
private struct NotificationSettingsView: View {
    @State private var feedNotificationAuthorizationStatus: FeedNotificationAuthorizationStatus = .unknown

    @AppStorage(NotificationSettings.isMasterEnabledKey)
    private var isMasterEnabled = NotificationSettings.defaultIsMasterEnabled

    @AppStorage(NotificationSettings.defaultEnabledForNewFeedsKey)
    private var isEnabledForNewFeeds = NotificationSettings.defaultEnabledForNewFeedsDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBlock(eyebrow: L10n.settingsNotificationsSection) {
                SettingRow(
                    title: L10n.settingsNotificationsPermissionTitle,
                    description: notificationPermissionDescription
                ) {
                    if feedNotificationAuthorizationStatus == .notDetermined {
                        Button(L10n.settingsNotificationsPermissionRequest) {
                            Task {
                                _ = await FeedNotificationService.requestAuthorization()
                                await refreshNotificationAuthorizationStatus()
                            }
                        }
                    } else if feedNotificationAuthorizationStatus == .denied {
                        Button(L10n.settingsNotificationsPermissionOpenSystemSettings) {
                            NotificationSettings.openSystemNotificationSettings()
                        }
                    } else {
                        Text(permissionStatusText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingRow(
                    title: L10n.settingsNotificationsMasterTitle,
                    description: L10n.settingsNotificationsMasterDescription
                ) {
                    Toggle("", isOn: $isMasterEnabled)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsNotificationsNewFeedsDefaultTitle,
                    description: L10n.settingsNotificationsNewFeedsDefaultDescription
                ) {
                    Toggle("", isOn: $isEnabledForNewFeeds)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsNotificationsTestTitle,
                    description: L10n.settingsNotificationsTestDescription
                ) {
                    Button(L10n.settingsNotificationsTestButton) {
                        Task {
                            await FeedNotificationService.presentTest()
                        }
                    }
                }

                InfoRow(
                    iconName: "dot.radiowaves.left.and.right",
                    title: L10n.settingsNotificationsFeedTitle,
                    description: L10n.settingsNotificationsFeedDescription
                )

                InfoRow(
                    iconName: "slider.horizontal.3",
                    title: L10n.settingsNotificationsRulesTitle,
                    description: L10n.settingsNotificationsRulesDescription
                )
            }
        }
        .task {
            await refreshNotificationAuthorizationStatus()
        }
    }
```

Die restlichen Members von `NotificationSettingsView` (`notificationPermissionDescription`, `permissionStatusText`, `refreshNotificationAuthorizationStatus()`, schließende `}`) bleiben unverändert — nur der `body` und die zwei neuen `@AppStorage`-Properties oberhalb davon ändern sich.

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Bestehende Testsuiten gegenprüfen (Regression)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/NotificationSettingsTests -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests -only-testing:FeedivoTests/FeedNotificationServiceTests -only-testing:FeedivoTests/RuleNotificationServiceTests`
Expected: PASS — alle vier Suiten grün.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift
git commit -m "Feature: Benachrichtigungs-Einstellungen — Master-Schalter, Neue-Feeds-Default, Test-Benachrichtigung, Systemeinstellungen-Link in der UI"
```

- [ ] **Step 5: Manuelle Live-Verifikation dokumentieren (nicht automatisierbar — kein computer-use für native macOS-Apps in dieser Umgebung)**

Checkliste für den Nutzer, in der nächsten "Aktuell in Arbeit"/"Letzte Änderungen"-Notiz in `CLAUDE.md` als ausstehend zu vermerken, bis der Nutzer sie bestätigt:

1. Einstellungen → Benachrichtigungen öffnen, alle vier neuen Zeilen sind sichtbar und beschriftet.
2. Master-Schalter ausschalten → "Test senden" klicken → Test-Benachrichtigung erscheint trotzdem (bewusstes `respectsMasterSwitch: false`-Verhalten).
3. Master-Schalter wieder einschalten, einen Feed mit aktivierter Benachrichtigung per echtem Refresh neue Artikel liefern lassen → Benachrichtigung erscheint.
4. Master-Schalter ausschalten, denselben Feed erneut refreshen → keine Benachrichtigung erscheint.
5. "Neue Feeds automatisch benachrichtigen" einschalten, neuen Feed hinzufügen, in dessen Feed-Eigenschaften prüfen, dass "Benachrichtigen" bereits aktiv ist.
6. macOS-Benachrichtigungserlaubnis für Feedivo in den Systemeinstellungen manuell auf "Blockieren" stellen, zurück in die App, Einstellungen → Benachrichtigungen öffnen → "Systemeinstellungen öffnen" klicken → prüfen, ob es tatsächlich zur Feedivo-eigenen Seite springt (nicht nur zur allgemeinen Übersicht). Springt es nicht korrekt, `NotificationSettings.appSpecificSystemSettingsURLString` durch `fallbackSystemSettingsURLString` ersetzen (Code-Änderung, kein Laufzeit-Fallback — siehe Spec-Risikoabschnitt) und Task 5 erneut committen.

---

## Self-Review

**Spec-Abdeckung:**
- Ziel 1 (Systemeinstellungen-Button) → Task 2 Step 4 (Key) + Task 5 Step 1 (UI-Zweig) + Task 5 Step 5 Punkt 6 (Live-Verifikation). ✅
- Ziel 2 (Master-Schalter) → Task 1 (Datenmodell) + Task 3 (Gate in `present`) + Task 5 (UI-Toggle). ✅
- Ziel 3 (Standard für neue Feeds) → Task 1 (Datenmodell) + Task 4 (Verdrahtung `addFeed`/OPML) + Task 5 (UI-Toggle). ✅
- Ziel 4 (Test-Benachrichtigung) → Task 3 (`presentTest()`) + Task 5 (UI-Button). ✅
- Ziel 5 (Stale-Text-Fix) → Task 2 Step 8. ✅
- Nicht-Ziele (pro-Feed/-Regel-Konfiguration, Klick-Navigation, neue Sound-Optionen) → keine Tasks berühren `FeedPropertiesView`/`RuleWizardView` oder fügen einen `UNUserNotificationCenterDelegate` hinzu. ✅

**Placeholder-Scan:** Keine TBD/TODO, jeder Code-Schritt enthält vollständigen Code, keine "siehe Task N"-Verweise ohne Wiederholung des Codes.

**Typkonsistenz:** `NotificationSettings.isMasterEnabled(in:)`/`isEnabledForNewFeeds(in:)` durchgängig mit `UserDefaults`-Parameter benannt; `respectsMasterSwitch` durchgängig `Bool` mit Default `true`; `SQLiteFeedSubscriptionService.userDefaults` durchgängig `UserDefaults` mit Default `.standard` — konsistent zwischen Task 1/3/4/5 verwendet.
