# Browser-Erweiterung: Popup-UX überarbeiten

**Datum:** 2026-07-13
**Status:** Zur Umsetzung freigegeben (Brainstorming abgeschlossen)
**Betrifft:** `BrowserExtensions/Chrome/` (Chrome + Safari, geteilte Dateien), `Feedivo/App/`, neue Server-Komponente in `Feedivo/Services/`

## Ausgangslage

Das Popup der Browser-Erweiterung (Feature 27) zeigt aktuell erkannte Feeds mit einem
"Titel", der aus `link.getAttribute("title") || document.title || href` stammt
(`BrowserExtensions/Shared/feedDetection.mjs`, dupliziert in
`BrowserExtensions/Chrome/content.js`, da MV3-Content-Scripts keine ES-Module
unterstützen). Viele Seiten setzen kein `title`-Attribut auf ihrem
`<link rel="alternate">`-Tag — der Feed erbt dann den Seitentitel. Hat eine Seite
mehrere Feeds (z. B. "Alle Artikel" + "Kommentare"), sehen beide Zeilen im Popup
identisch aus. Fallback-Pfade (`/feed`, `/rss`, gefunden per HEAD-Request-Heuristik,
siehe `probeFallbackFeedPaths`) zeigen zusätzlich nur ihren Pfad als Label.

Nutzer-Report (2026-07-13): Popup soll benutzerfreundlicher werden — konkret genannt:
echte/unterscheidbare Feed-Namen, sichtbare Rückmeldung nach "Hinzufügen", unklare
Fallback-Pfad-Labels, kein Hinweis ob ein Feed bereits abonniert ist, unfertig
wirkendes Layout.

Der `feedivo://add`-Deep-Link (Feature 23.2, `FeedivoURLSchemeParser` +
`FeedivoAppDelegate`) ist aktuell reines Fire-and-Forget: die Erweiterung öffnet die
URL und schließt sofort das Popup, ohne je zu erfahren, ob das Hinzufügen geklappt hat
oder der Feed schon existierte.

## Ziel

1. Im Popup werden die **echten** Feed-Namen angezeigt (aus dem Feed-Inhalt selbst),
   nicht mehr Seitentitel oder rohe Pfade.
2. Die Erweiterung kann die laufende Feedivo-App fragen, ob ein Feed schon abonniert
   ist, und beim Hinzufügen eine echte Erfolgs-/Fehler-/Duplikat-Rückmeldung bekommen
   — ohne dass die App-UI in den Vordergrund muss.
3. Läuft die App nicht, verhält sich die Erweiterung wie bisher (Deep-Link-Fallback).
4. Kleineres visuelles Polish (Favicon, Zweitzeile mit URL) für bessere
   Unterscheidbarkeit bei mehreren Feeds.

## Abschnitt A — Echte Feed-Namen per Fetch + Parse

Statt der bisherigen String-Heuristik lädt die Erweiterung beim Seiten-Scan
(`content.js`, bzw. `detectFeeds()` in `feedDetection.mjs`) für jeden erkannten
Feed-Kandidaten (sowohl aus `<link>`-Tags als auch aus den Fallback-Pfaden) zusätzlich
per `fetch()` den tatsächlichen Feed-Inhalt (gleiche Origin wie die Seite, keine neue
Extension-Permission nötig) und parst den echten Titel:

- RSS: `channel > title` (per `DOMParser`, `application/xml`)
- Atom: `feed > title` (per `DOMParser`)
- JSON Feed: `title`-Feld (per `JSON.parse`)

Reihenfolge der Titel-Auflösung pro Feed:

1. Titel aus dem geparsten Feed-Inhalt (bevorzugt, immer versucht)
2. Bei Fetch-/Parse-Fehler (Netzwerk, CORS, kaputtes XML/JSON): Fallback auf die
   bisherige Heuristik `link.title || document.title || href` — für `<link>`-Funde;
   für Fallback-Pfad-Funde einfach der Pfad selbst (`"/feed"` etc.), wie bisher.

Das löst gleichzeitig das "Fallback-Pfade unklar benannt"-Problem, weil auch per
Pfad-Heuristik gefundene Feeds jetzt (wenn erreichbar) ihren echten Namen zeigen.

Die Fetches laufen parallel (`Promise.all`) beim Seiten-Scan, **bevor** das Popup
geöffnet wird — das Popup zeigt also weiterhin sofort fertige Daten, keine zusätzliche
Wartezeit beim Öffnen.

**Wichtig:** `content.js` (Chrome/Safari, kein ES-Module-Support in MV3
Content-Scripts) und `Shared/feedDetection.mjs` (Node-getestet) müssen bei dieser
neuen Logik weiterhin synchron gehalten werden — bestehende, bereits dokumentierte
Einschränkung dieses Feature-Bereichs.

## Abschnitt B — Lokaler HTTP-Server in der App

### Warum kein Native Messaging Host

Der von Chrome/Safari vorgesehene "offizielle" Weg für Erweiterung-zu-App-Kommunikation
wäre ein Native Messaging Host: eigener Prozess, der über stdin/stdout im
längenpräfixierten JSON-Protokoll spricht, plus ein Host-Manifest, das pro Browser an
einem festen Systempfad installiert werden muss. Für eine privat verteilte App (kein
Store-Vertrieb) ein spürbar höherer Installations- und Wartungsaufwand als ein lokaler
HTTP-Server. Entscheidung: lokaler HTTP-Server.

### Server

`FeedivoApp.swift` startet beim App-Start (analog zum bestehenden Muster für
Hintergrund-Refresh-Registrierung und DB-Öffnung) einen minimalen HTTP-Server:

- **Bindung:** ausschließlich `127.0.0.1` (Loopback), niemals `0.0.0.0`
- **Port:** fest `51823` (kein UI zur Konfiguration in v1)
- **Implementierung:** `Network.framework` (`NWListener`), neue Datei
  `Feedivo/Services/LocalExtensionBridgeServer.swift` (Name vorläufig)
- **Neues Entitlement:** `com.apple.security.network.server` in
  `Feedivo/Feedivo.entitlements` (App ist sandboxed, aktuell nur `network.client`
  vorhanden — Ergänzung unproblematisch bei privater Verteilung)
- Serverstart/-fehler (z. B. Port bereits belegt) wird über `AppLogger.dataAccess`
  geloggt, **nicht** als Nutzer-Alert — die App bleibt in jedem Fall voll
  funktionsfähig, die Erweiterung fällt bei einem nicht erreichbaren Server einfach
  auf ihr bisheriges Verhalten zurück (siehe Abschnitt C/D)

### Endpunkte

| Methode & Pfad | Request | Response |
|---|---|---|
| `GET /status?url=<feedURL>` | — | `{ "subscribed": true \| false }` — Abgleich gegen `FeedStore` |
| `POST /add` | `Content-Type: application/json`, Body `{ "url": "..." }` | `{ "result": "added" \| "alreadyExists" \| "error", "message": "..." }` |

`POST /add` nutzt intern denselben `SQLiteFeedSubscriptionService`, den auch der
`feedivo://add`-Deep-Link bereits verwendet — keine zweite Hinzufügen-Logik.

Der erzwungene `Content-Type: application/json`-Header auf `POST /add` löst im Browser
einen CORS-Preflight (`OPTIONS`) aus. Da der Server keinen
`Access-Control-Allow-Origin`-Header für fremde Web-Origins setzt, kann eine normale
Webseite (nicht unsere Erweiterung) diesen Preflight nicht erfolgreich abschließen —
das schützt vor blindem Cross-Site-POST durch beliebige Seiten, während Feedivo läuft.
Die Erweiterung selbst ruft den Server aus ihrem Background-/Popup-Kontext auf, der
nicht denselben Origin-Restriktionen unterliegt wie Seiten-JavaScript.
**Bekannte Grenze für v1:** kein Shared-Secret/Token — das ist ein bewusster,
dokumentierter Kompromiss (gleiches Schutzniveau wie der bereits bestehende, ebenfalls
unauthentifizierte `feedivo://add`-Deep-Link). Kann bei Bedarf später nachgerüstet
werden.

## Abschnitt C — Popup-UX

Beim Öffnen fragt `popup.js` für jeden angezeigten Feed parallel
`GET /status?url=...` ab (kurzes Timeout, ca. 300 ms). Pro Zeile:

- **Bereits abonniert:** Button-Text „Bereits in Feedivo" (deaktiviert), dezentes
  Checkmark-Icon vor dem Titel.
- **Noch nicht abonniert:** Button „Zu Feedivo hinzufügen" wie bisher.

Klick-Flow auf "Hinzufügen":

1. `POST /add` versuchen.
2. Erfolg (`"added"`) → Zeile zeigt kurz „✓ Hinzugefügt" (Button ausgeblendet),
   Popup schließt sich automatisch nach ca. 1,5 s.
3. `"alreadyExists"` → wie „bereits abonniert" behandeln (kein Fehlerzustand).
4. Request schlägt fehl (App läuft nicht, Timeout, Netzwerkfehler) → Fallback auf
   bisheriges Verhalten: `feedivo://add?url=...` öffnen, Popup sofort schließen wie
   heute.
5. Server antwortet mit `"error"` oder HTTP 400 (ungültige URL) → kurze Inline-
   Fehlermeldung in der Zeile statt stillem Fehlschlag.

### Visuelles Polish

- Favicon der aktiven Seite (`activeTab.favIconUrl`, kein zusätzlicher Request) links
  vor jeder Zeile.
- Feed-URL als kleine, gedämpfte Zweitzeile unter dem (jetzt echten) Titel — hilft bei
  mehreren ähnlich benannten Feeds zur Unterscheidung.

## Abschnitt D — Fehlerfälle & Tests

### Fehlerfälle

- Feed-Fetch (Titel-Auflösung) schlägt fehl → Fallback auf alte Heuristik (Abschnitt A).
- Lokaler Server nicht erreichbar → Status-Abfrage wird still übersprungen (kein
  Badge), "Hinzufügen" fällt auf Deep-Link zurück (Abschnitt C, Punkt 4).
- `POST /add` liefert `"alreadyExists"` → als „bereits abonniert" behandelt, nicht als
  Fehler.
- Ungültige/fehlende `url` → Server antwortet 400, Popup zeigt Inline-Fehlermeldung.

### Tests

- `BrowserExtensions/Shared/feedDetection.test.mjs`: neue Fälle für die Fetch+Parse-
  Titel-Logik (RSS/Atom/JSON Feed, Fetch-Fehler-Fallback), nutzt das bestehende
  `fetchImpl`-Injektionsmuster.
- Neue Swift-Testsuite (Swift Testing, kein XCTest) für die Server-Request-Logik:
  Routing/Verarbeitung von `/status` und `/add` als eigene, von der reinen
  `NWListener`-Socket-Verdrahtung getrennte, injizierbare/testbare Einheit — Tests
  laufen ohne echten Netzwerk-Bind.
- Bestehende Tests für `feedivo://add`/`SQLiteFeedSubscriptionService` bleiben
  unverändert gültig (keine Verhaltensänderung an der eigentlichen Hinzufügen-Logik,
  nur ein zweiter Aufrufweg).

## Nicht im Scope (bewusst zurückgestellt)

- Konfigurierbarer Port / Server ein-/ausschaltbar in den Einstellungen.
- Shared-Secret/Token-Absicherung des lokalen Servers.
- Native Messaging Host als Alternative/Ergänzung.
